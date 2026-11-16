import XCTest
import AppKit
@testable import AppUninstaller

final class UninstallRegressionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("UninstallRegression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func makeFile(_ relativePath: String) throws -> URL {
        let path = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: path)
        return path
    }

    @MainActor
    private func makeApp() throws -> InstalledApp {
        _ = try makeFile("Fixture.app/Contents/fixture")
        return InstalledApp(name: "Fixture", path: root.appendingPathComponent("Fixture.app"),
                            bundleIdentifier: "test.fixture", icon: NSImage(), size: 7)
    }

    private func makeRemover(failing paths: Set<URL> = []) -> FileRemover {
        let root = root!
        return FileRemover(trashItem: { url in
            if paths.contains(url) { throw POSIXError(.EACCES) }
            let trash = root.appendingPathComponent("trash", isDirectory: true)
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(UUID().uuidString))
        }, recordFailure: { _ in })
    }

    @MainActor
    func testRemovedBundleLeavesListEvenWhenResidualFails() async throws {
        let app = try makeApp()
        let residual = try makeFile("container/data")
        app.residualFiles = [ResidualFile(path: residual, type: .containers, size: 7)]
        let scanner = AppScanner(residualScanner: ResidualFileScanner(homeDirectory: root))
        scanner.apps = [app]

        let result = await makeRemover(failing: [residual]).removeApp(app)
        scanner.applyRemovalResult(result, to: app)

        XCTAssertTrue(result.appRemoved)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failedPaths, [residual])
        XCTAssertTrue(scanner.apps.isEmpty)
        XCTAssertEqual(app.residualFiles.map(\.path), [residual])
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: residual.path))
    }

    @MainActor
    func testFailedBundlePreservesAssociatedDataAndRemainsListed() async throws {
        let app = try makeApp()
        let residual = try makeFile("preferences.plist")
        app.residualFiles = [ResidualFile(path: residual, type: .preferences, size: 7)]
        let scanner = AppScanner(residualScanner: ResidualFileScanner(homeDirectory: root))
        scanner.apps = [app]

        let result = await makeRemover(failing: [app.path]).removeApp(app)
        scanner.applyRemovalResult(result, to: app)

        XCTAssertFalse(result.appRemoved)
        XCTAssertEqual(result.failedPaths, [app.path])
        XCTAssertEqual(scanner.apps.map(\.id), [app.id])
        XCTAssertEqual(app.residualFiles.map(\.path), [residual])
        XCTAssertTrue(FileManager.default.fileExists(atPath: residual.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path.path))
    }

    @MainActor
    func testBundleFailureStopsBeforeAnyResidualAttempt() async throws {
        let app = try makeApp()
        let residual = try makeFile("container/data")
        app.residualFiles = [ResidualFile(path: residual, type: .containers, size: 7)]
        let result = await makeRemover(failing: [residual, app.path]).removeApp(app)
        XCTAssertEqual(result.failedPaths, [app.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: residual.path))
        XCTAssertFalse(result.appRemoved)
    }

    @MainActor
    func testResidualOnlyRemovalPreservesBundleAndUnselectedFiles() async throws {
        let app = try makeApp()
        let selected = try makeFile("selected.plist")
        let kept = try makeFile("kept.plist")
        let unselected = ResidualFile(path: kept, type: .preferences, size: 7)
        unselected.isSelected = false
        app.residualFiles = [ResidualFile(path: selected, type: .preferences, size: 7), unselected]
        let scanner = AppScanner(residualScanner: ResidualFileScanner(homeDirectory: root))
        scanner.apps = [app]

        let result = await makeRemover().removeResidualFiles(of: app)
        scanner.applyRemovalResult(result, to: app)

        XCTAssertFalse(result.appRemoved)
        XCTAssertEqual(scanner.apps.map(\.id), [app.id])
        XCTAssertEqual(app.residualFiles.map(\.path), [kept])
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    @MainActor
    func testAlreadyMissingTargetsAreNotFailuresOrCountedAsFreedSpace() async throws {
        let app = try makeApp()
        try FileManager.default.removeItem(at: app.path)
        let missing = root.appendingPathComponent("already-removed.plist")
        app.residualFiles = [ResidualFile(path: missing, type: .preferences, size: 20)]
        let result = await makeRemover().removeApp(app, moveToTrash: false)
        XCTAssertTrue(result.appRemoved)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.totalSizeRemoved, 0)
        XCTAssertEqual(Set(result.completedPaths), [missing, app.path])
    }

    @MainActor
    func testMissingChildErrorDoesNotMarkExistingBundleAsRemoved() async throws {
        let app = try makeApp()
        let remover = FileRemover(trashItem: { _ in throw CocoaError(.fileNoSuchFile) }, recordFailure: { _ in })
        let result = await remover.removeApp(app)
        XCTAssertFalse(result.appRemoved)
        XCTAssertEqual(result.failedPaths, [app.path])
    }

    @MainActor
    func testRemovalInvalidatesCacheAndNextScanFindsNewResidual() async throws {
        let app = try makeApp()
        let old = try makeFile("Library/Preferences/test.fixture.plist")
        let residualScanner = ResidualFileScanner(homeDirectory: root)
        let scanner = AppScanner(residualScanner: residualScanner)
        scanner.apps = [app]
        await scanner.scanResidualFiles(for: app)
        XCTAssertEqual(app.residualFiles.map { $0.path.resolvingSymlinksInPath().path }, [old.resolvingSymlinksInPath().path])

        let added = try makeFile("Library/Caches/test.fixture/new-cache")
        let result = await makeRemover().removeApp(app, includeApp: false)
        scanner.applyRemovalResult(result, to: app)
        await scanner.scanResidualFiles(for: app)

        XCTAssertEqual(app.residualFiles.map { $0.path.resolvingSymlinksInPath().path },
                       [added.deletingLastPathComponent().resolvingSymlinksInPath().path])
        XCTAssertEqual(scanner.apps.map(\.id), [app.id])
    }

    @MainActor
    func testRepeatedPartialRemovalOnlyRetriesRemainingResidual() async throws {
        let app = try makeApp()
        let residual = try makeFile("denied.plist")
        app.residualFiles = [ResidualFile(path: residual, type: .preferences, size: 7)]
        let remover = makeRemover(failing: [residual])
        let first = await remover.removeApp(app)
        let second = await remover.removeApp(app)
        XCTAssertTrue(first.appRemoved)
        XCTAssertTrue(second.appRemoved)
        XCTAssertEqual(second.failedPaths, [residual])
        XCTAssertEqual(second.successCount, 0)
        XCTAssertEqual(second.totalSizeRemoved, 0)
    }

    func testFailureJournalPersistsPathReasonAndSystemCodes() throws {
        let path = try makeFile("denied.plist")
        let logs = root.appendingPathComponent("logs")
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError, userInfo: [
            NSLocalizedDescriptionKey: "Fixture permission denied",
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        ])
        let service = DeletionLogService(logDirectory: logs, moveToTrash: { _ in throw error })
        XCTAssertFalse(service.logAndDelete(at: path, category: "AppUninstall"))
        let files = try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].lastPathComponent.hasPrefix("failures_"))
        let records = try JSONDecoder().decode([DeletionFailureRecord].self, from: Data(contentsOf: files[0]))
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.category, "AppUninstall")
        XCTAssertEqual(record.failure.path, path)
        XCTAssertEqual(record.failure.message, "Fixture permission denied")
        XCTAssertEqual(record.failure.errorDomain, NSCocoaErrorDomain)
        XCTAssertEqual(record.failure.errorCode, NSFileWriteNoPermissionError)
        XCTAssertEqual(record.failure.underlyingErrorDomain, NSPOSIXErrorDomain)
        XCTAssertEqual(record.failure.underlyingErrorCode, Int(EACCES))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    @MainActor
    func testRemoverReturnsAndRecordsTheSameFailure() async throws {
        let app = try makeApp()
        var failures: [RemovalFailure] = []
        let remover = FileRemover(trashItem: { _ in throw POSIXError(.EPERM) }, recordFailure: { failures.append($0) })
        let result = await remover.removeApp(app)
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.path, result.failures.first?.path)
        XCTAssertEqual(failures.first?.errorCode, Int(EPERM))
        XCTAssertFalse(try XCTUnwrap(result.failures.first?.message).isEmpty)
    }

    func testConcurrentFailureLoggingDoesNotLoseRecords() throws {
        let logs = root.appendingPathComponent("logs")
        let service = DeletionLogService(logDirectory: logs, moveToTrash: { _ in nil })
        let fixtureRoot = root!
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            let failure = RemovalFailure(path: fixtureRoot.appendingPathComponent("denied-\(index)"), error: POSIXError(.EACCES))
            service.logFailure(failure, category: "AppUninstall")
        }
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil).first)
        let records = try JSONDecoder().decode([DeletionFailureRecord].self, from: Data(contentsOf: file))
        XCTAssertEqual(records.count, 12)
        XCTAssertEqual(Set(records.map { $0.failure.path }).count, 12)
    }
    @MainActor
    func testRemovalWorkerKeepsMainActorResponsiveAndCancellationPreservesRemainingFile() async throws {
        let first = try makeFile("first.data")
        let second = try makeFile("second.data")
        let entered = expectation(description: "worker started")
        let release = DispatchSemaphore(value: 0)
        let remover = FileRemover(trashItem: { url in
            XCTAssertFalse(Thread.isMainThread)
            if url == first {
                entered.fulfill()
                _ = release.wait(timeout: .now() + 3)
            }
            try FileManager.default.removeItem(at: url)
        }, recordFailure: { _ in })
        let task = Task { await remover.removePaths([(first, 7), (second, 7)]) }
        await fulfillment(of: [entered], timeout: 2)
        // This main-actor continuation runs while the I/O worker is waiting.
        task.cancel()
        release.signal()
        let result = await task.value
        XCTAssertEqual(result.completedPaths, [first])
        XCTAssertTrue(result.failedPaths.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

}
