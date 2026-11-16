import XCTest
@testable import AppUninstaller

final class ProductHardeningRegressionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ProductHardening-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    @MainActor func testJournalRestoresQuotedNameWithoutOverwritingNewFileAndPersistsState() async throws {
        let trash = root.appendingPathComponent("Trash")
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("report's $literal.txt")
        try Data("original".utf8).write(to: original)
        let journal = DeletionLogService(logDirectory: logs, moveToTrash: { url in
            let target = trash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            return target
        })
        try journal.trashItem(at: original, category: "SpaceLens")
        await Task.yield()
        journal.loadAllLogs()
        for _ in 0..<50 where journal.deletionRecords.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        let record = try XCTUnwrap(journal.deletionRecords.first)
        try Data("new".utf8).write(to: original)
        do { try await journal.restoreRecord(record); XCTFail("Must reject destination conflict") }
        catch { XCTAssertEqual((error as NSError).code, NSFileWriteFileExistsError) }
        XCTAssertEqual(try String(contentsOf: original), "new")
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.trashPath!))
        try FileManager.default.removeItem(at: original)
        try await journal.restoreRecord(record)
        XCTAssertEqual(try String(contentsOf: original), "original")
        journal.loadAllLogs()
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(journal.deletionRecords.first?.isRestored, true)
    }

    @MainActor func testSpaceLensReportsUnreadableScopeInsteadOfSilentEmptyResult() async {
        let scanner = SpaceLensScanner()
        await scanner.scan(targetURL: root.appendingPathComponent("missing"))
        XCTAssertFalse(scanner.inaccessiblePaths.isEmpty)
        XCTAssertFalse(scanner.isScanning)
    }

    @MainActor func testCancelledLazyLoadDoesNotAttachChildren() async throws {
        let folder = root.appendingPathComponent("deep")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1,2,3]).write(to: folder.appendingPathComponent("file"))
        let scanner = SpaceLensScanner()
        let node = FileNode(url: folder, name: "deep", size: 3, isDirectory: true, childrenLoaded: false)
        let task = Task { await scanner.loadChildren(for: node) }
        task.cancel()
        await task.value
        XCTAssertFalse(node.childrenLoaded)
        XCTAssertTrue(node.children.isEmpty)
    }

    func testDiskIOUsesElapsedTimeAndRejectsCounterReset() {
        let sampler = DiskIOSampler()
        XCTAssertNil(sampler.sample(counters: .init(read: 100, written: 200), at: 1))
        let rates = sampler.sample(counters: .init(read: 500, written: 1200), at: 3)
        XCTAssertEqual(rates?.read, 200)
        XCTAssertEqual(rates?.written, 500)
        XCTAssertNil(sampler.sample(counters: .init(read: 0, written: 0), at: 5))
        XCTAssertNil(sampler.sample(counters: .init(read: 100, written: 100), at: 5))
    }

    @MainActor func testTaskCenterRequestsCancellationAndWaitsForOwnerOutcome() {
        let center = OperationCenter()
        var cancellationCount = 0
        let id = center.begin(title: "fixture") { cancellationCount += 1 }
        center.cancel(id: id)
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(center.records.first?.state, .running)
        center.finish(id: id, state: .cancelled, detail: "Stopped")
        center.cancel(id: id)
        XCTAssertEqual(cancellationCount, 1)
        XCTAssertEqual(center.records.first?.state, .cancelled)
    }
}
