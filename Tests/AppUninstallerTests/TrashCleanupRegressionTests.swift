import XCTest
import AppKit
@testable import AppUninstaller

private actor TrashCleanupGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor TrashCleanupProbe {
    private(set) var calls = 0
    func record() { calls += 1 }
}

final class TrashCleanupRegressionTests: XCTestCase {
    private var root: URL!
    private var trash: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("TrashCleanupRegression-\(UUID().uuidString)").resolvingSymlinksInPath()
        trash = root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    private func item(_ url: URL, size: Int64 = 1, selected: Bool = true) -> TrashItem {
        TrashItem(url: url, name: url.lastPathComponent, size: size, dateDeleted: nil, isDirectory: false, isSelected: selected)
    }

    @MainActor
    func testStopKeepsScanOwnershipAndPreventsCleanupOrRestartUntilExit() async {
        let gate = TrashCleanupGate()
        let probe = TrashCleanupProbe()
        let file = trash.appendingPathComponent("fixture")
        let scanner = TrashScanner(trashURL: trash, listItems: { _ in
            await probe.record()
            return [file]
        }, measureSize: { _ in await gate.wait(); return 5 }, recordFailure: { _ in })
        let task = Task { await scanner.scan() }
        let entered = await waitUntil { await probe.calls == 1 }
        XCTAssertTrue(entered)
        scanner.stopScan()
        scanner.reset()
        XCTAssertTrue(scanner.isScanning)
        XCTAssertTrue(scanner.isStoppingScan)
        await scanner.scan()
        let removed = await scanner.emptyTrash()
        XCTAssertEqual(removed, 0)
        let count = await probe.calls
        XCTAssertEqual(count, 1)
        await gate.open()
        await task.value
        XCTAssertFalse(scanner.isScanning)
        XCTAssertTrue(scanner.isStopped)
        XCTAssertTrue(scanner.items.isEmpty)
        await scanner.scan()
        XCTAssertFalse(scanner.isStopped)
        XCTAssertEqual(scanner.items.count, 1)
        XCTAssertEqual(scanner.totalSize, 5)
    }

    @MainActor
    func testPermanentDeletionOnlyRemovesSelectedFixtureChildren() async throws {
        let selected = trash.appendingPathComponent("selected")
        let keep = trash.appendingPathComponent("keep")
        try Data(repeating: 1, count: 5).write(to: selected)
        try Data(repeating: 2, count: 9).write(to: keep)
        let scanner = TrashScanner(trashURL: trash, recordFailure: { _ in })
        await scanner.scan()
        for index in scanner.items.indices { scanner.items[index].isSelected = scanner.items[index].url.lastPathComponent == "selected" }
        let removed = await scanner.emptyTrash()
        XCTAssertEqual(removed, 5)
        XCTAssertEqual(scanner.cleanedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: selected.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
        XCTAssertEqual(scanner.items.count, 1)
    }

    @MainActor
    func testRootOutsidePathAndSymlinkAncestorCannotBePermanentlyDeleted() async throws {
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let victim = outside.appendingPathComponent("victim")
        try Data([1, 2, 3]).write(to: victim)
        let link = trash.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let scanner = TrashScanner(trashURL: trash, recordFailure: { _ in })
        scanner.items = [item(trash), item(victim), item(link.appendingPathComponent("victim"))]
        let removed = await scanner.emptyTrash()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(scanner.deletionFailures.count, 3)
        XCTAssertEqual(scanner.failedDeletionCount, 3)
        XCTAssertEqual(scanner.items.count, 3)
        XCTAssertEqual(try Data(contentsOf: victim), Data([1, 2, 3]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
    }

    @MainActor
    func testDeletingDirectSymlinkRemovesOnlyLink() async throws {
        let target = root.appendingPathComponent("outside-file")
        try Data([4, 5]).write(to: target)
        let link = trash.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let scanner = TrashScanner(trashURL: trash, recordFailure: { _ in })
        await scanner.scan()
        XCTAssertEqual(scanner.totalSize, 0, "A symlink does not claim its target's size")
        _ = await scanner.emptyTrash()
        XCTAssertEqual(scanner.cleanedCount, 1)
        XCTAssertEqual(try Data(contentsOf: target), Data([4, 5]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
    }

    @MainActor
    func testFailurePreservesItemAndOriginalReasonAndDeduplicatesAttempts() async {
        let probe = TrashCleanupProbe()
        let file = trash.appendingPathComponent("denied")
        var logged: [RemovalFailure] = []
        let scanner = TrashScanner(trashURL: trash, removeItem: { _ in
            await probe.record()
            throw CocoaError(.fileWriteNoPermission)
        }, recordFailure: { logged.append($0) })
        scanner.items = [item(file, size: 10), item(file, size: 10)]
        let removed = await scanner.emptyTrash()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(scanner.items.count, 2)
        XCTAssertEqual(scanner.totalSize, 10)
        XCTAssertEqual(scanner.deletionFailures.first?.errorCode, NSFileWriteNoPermissionError)
        XCTAssertEqual(logged.count, 1)
        let attempts = await probe.calls
        XCTAssertEqual(attempts, 1)
    }

    @MainActor
    func testStoppingCleanupKeepsOwnershipAndUnprocessedItems() async throws {
        let first = trash.appendingPathComponent("first")
        let second = trash.appendingPathComponent("second")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let gate = TrashCleanupGate()
        let probe = TrashCleanupProbe()
        let scanner = TrashScanner(trashURL: trash, removeItem: { url in
            await probe.record()
            await gate.wait()
            try FileManager.default.removeItem(at: url)
        }, recordFailure: { _ in })
        scanner.items = [item(first), item(second)]
        let task = Task { await scanner.emptyTrash() }
        let entered = await waitUntil { await probe.calls == 1 }
        XCTAssertTrue(entered)
        scanner.stopCleaning()
        scanner.reset()
        await scanner.scan()
        XCTAssertTrue(scanner.isCleaning)
        XCTAssertEqual(scanner.items.count, 2)
        await gate.open()
        let removed = await task.value
        XCTAssertEqual(removed, 1)
        XCTAssertFalse(scanner.isCleaning)
        XCTAssertTrue(scanner.cleaningWasStopped)
        XCTAssertEqual(scanner.items.map(\.url), [second])
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    @MainActor
    func testReplacingTrashRootWithSymlinkIsRejected() async throws {
        let original = trash.appendingPathComponent("file")
        try Data([1]).write(to: original)
        let scanner = TrashScanner(trashURL: trash, recordFailure: { _ in })
        await scanner.scan()
        let preserved = root.appendingPathComponent("preserved")
        try FileManager.default.moveItem(at: trash, to: preserved)
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let victim = outside.appendingPathComponent("file")
        try Data([2]).write(to: victim)
        try FileManager.default.createSymbolicLink(at: trash, withDestinationURL: outside)
        let removed = await scanner.emptyTrash()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(scanner.deletionFailures.count, 1)
        XCTAssertEqual(try Data(contentsOf: victim), Data([2]))
        XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent("file")), Data([1]))
    }

    @MainActor
    func testPreexistingTrashRootSymlinkNeverTrustsOrDeletesTarget() async throws {
        try FileManager.default.removeItem(at: trash)
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appendingPathComponent("sentinel")
        try Data([7, 8, 9]).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: trash, withDestinationURL: outside)
        let scanner = TrashScanner(trashURL: trash, recordFailure: { _ in })
        XCTAssertEqual(scanner.trashURL.standardizedFileURL.path, trash.standardizedFileURL.path)
        await scanner.scan()
        XCTAssertTrue(scanner.items.isEmpty)
        XCTAssertEqual(scanner.scanFailure?.errorDomain, "MacOptimizer.TrashSafety")
        XCTAssertFalse(scanner.hasCompletedScan)
        scanner.items = [item(trash.appendingPathComponent("sentinel"), size: 3)]
        let removed = await scanner.emptyTrash()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(scanner.deletionFailures.count, 1)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([7, 8, 9]))
    }

    @MainActor
    func testTrashScanPermissionFailurePreservesOriginalReason() async {
        let scanner = TrashScanner(trashURL: trash, listItems: { _ in
            throw CocoaError(.fileReadNoPermission)
        }, recordFailure: { _ in })
        await scanner.scan()
        XCTAssertTrue(scanner.needsPermission)
        XCTAssertEqual(scanner.scanFailure?.errorCode, NSFileReadNoPermissionError)
        XCTAssertFalse(scanner.hasCompletedScan)
        XCTAssertFalse(scanner.isScanning)
    }

}
