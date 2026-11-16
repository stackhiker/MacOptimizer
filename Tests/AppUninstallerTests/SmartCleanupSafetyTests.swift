import XCTest
import Darwin
@testable import AppUninstaller

private actor SmartCleanupTestGate {
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func hasEntered() -> Bool { entered }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

final class SmartCleanupSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SmartCleanupSafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func age(_ url: URL, days: Int) throws {
        let seconds = Int(Date().addingTimeInterval(-Double(days) * 86400).timeIntervalSince1970)
        let timestamps = [timeval(tv_sec: seconds, tv_usec: 0), timeval(tv_sec: seconds, tv_usec: 0)]
        let result = timestamps.withUnsafeBufferPointer { buffer in
            url.path.withCString { utimes($0, buffer.baseAddress) }
        }
        XCTAssertEqual(result, 0)
    }

    func testPersistentDataRootsAreNeverAutomaticJunk() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for suffix in ["Library/WebKit", "Library/HTTPStorages", "Library/Saved Application State",
                       "Library/Developer/Xcode/Archives", "Library/Developer/CoreSimulator/Devices",
                       "Library/pnpm", ".gem", ".m2/repository", "Library/Application Support/MobileSync/Backup",
                       "Library/Application Support/Code/User/workspaceStorage"] {
            XCTAssertFalse(SafetyGuard.shared.isSafeToDelete(home.appendingPathComponent(suffix)), suffix)
            XCTAssertFalse(SafetyGuard.shared.isSafeToDelete(home.appendingPathComponent(suffix).appendingPathComponent("fixture.data")), suffix)
        }
    }

    func testTemporaryCleanupKeepsNewFilesDirectoriesAndNestedFiles() throws {
        let old = root.appendingPathComponent("old.tmp")
        let fresh = root.appendingPathComponent("fresh.tmp")
        let activeDirectory = root.appendingPathComponent("active-build")
        try Data([1]).write(to: old)
        try Data([2]).write(to: fresh)
        try FileManager.default.createDirectory(at: activeDirectory, withIntermediateDirectories: true)
        let nested = activeDirectory.appendingPathComponent("old-but-active.tmp")
        try Data([3]).write(to: nested)
        try age(old, days: 30)
        try age(nested, days: 30)
        try age(activeDirectory, days: 30)
        let eligible = TemporaryCleanupPolicy.eligibleFiles(in: root)
        XCTAssertEqual(eligible.map(\.lastPathComponent), ["old.tmp"])
        XCTAssertFalse(TemporaryCleanupPolicy.isEligible(nested, in: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testTemporaryCleanupRejectsSymbolicAndHardLinks() throws {
        let file = root.appendingPathComponent("file.tmp")
        try Data([1]).write(to: file)
        try age(file, days: 30)
        let symbolic = root.appendingPathComponent("symbolic")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: file)
        XCTAssertFalse(TemporaryCleanupPolicy.isEligible(symbolic, in: root))
        let hard = root.appendingPathComponent("hard")
        try FileManager.default.linkItem(at: file, to: hard)
        XCTAssertFalse(TemporaryCleanupPolicy.isEligible(hard, in: root))
        XCTAssertFalse(TemporaryCleanupPolicy.isEligible(file, in: root))
    }

    func testTemporaryEligibilityIsRecheckedAfterFileBecomesActive() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("SmartCleanupRecheck-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data([1]).write(to: file)
        try age(file, days: 30)
        XCTAssertTrue(SafetyGuard.shared.isSafeToDelete(file))
        try age(file, days: 0)
        XCTAssertFalse(SafetyGuard.shared.isSafeToDelete(file))
    }

    @MainActor
    func testOrdinaryFileAndHiddenDirectoryContentsHaveCorrectLogicalSize() throws {
        let file = root.appendingPathComponent("ordinary.log")
        try Data(repeating: 1, count: 37).write(to: file)
        try Data(repeating: 2, count: 11).write(to: root.appendingPathComponent(".hidden"))
        let service = SmartCleanerService()
        XCTAssertEqual(service.calculateSize(at: file), 37)
        XCTAssertEqual(service.calculateSize(at: root), 48)
    }

    @MainActor
    func testAncestorDedupWorksEvenWhenChildIsEncounteredFirst() async {
        let parent = CleanerFileItem(url: root.appendingPathComponent("cache"), name: "cache", size: 100, groupId: "cache", isDirectory: true)
        let child = CleanerFileItem(url: parent.url.appendingPathComponent("child"), name: "child", size: 30, groupId: "cache", isDirectory: false)
        var calls: [URL] = []
        let service = SmartCleanerService(cleanupFile: { url, permanent in
            XCTAssertFalse(permanent)
            calls.append(url)
            return true
        }, deletionAllowed: { _, _ in true })
        service.systemCacheFiles = [child]
        service.userCacheFiles = [parent, parent]
        XCTAssertEqual(service.systemJunkTotalSize, 100)
        let result = await service.cleanAll()
        XCTAssertEqual(calls, [parent.url])
        XCTAssertEqual(result.success, 1)
        XCTAssertEqual(result.size, 100)
        XCTAssertEqual(service.totalMovedToTrashSize, 100)
        XCTAssertTrue(service.systemCacheFiles.isEmpty)
        XCTAssertTrue(service.userCacheFiles.isEmpty)
    }

    @MainActor
    func testGenericCleanupRefusesTrashRootAndChildrenEvenWithInjectedAllow() async {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let service = SmartCleanerService(cleanupFile: { _, _ in
            XCTFail("Generic Run must never empty Trash")
            return true
        }, deletionAllowed: { _, _ in true })
        service.trashFiles = [CleanerFileItem(url: trash, name: "Trash", size: 100, groupId: "trash", isDirectory: true)]
        let result = await service.cleanAll()
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.size, 0)
        XCTAssertEqual(service.totalMovedToTrashSize, 0)
        let child = CleanerFileItem(url: trash.appendingPathComponent("fixture"), name: "fixture", size: 1, groupId: "trash", isDirectory: false)
        let deletedChild = await service.deleteSingleFile(child, from: .largeFiles)
        XCTAssertFalse(deletedChild)
    }

    @MainActor
    func testLegacySingleDeleteUsesTrashAndSameProtection() async {
        let item = CleanerFileItem(url: root.appendingPathComponent("fixture"), name: "fixture", size: 1, groupId: "cache", isDirectory: false)
        var called = false
        let refused = SmartCleanerService(cleanupFile: { _, _ in called = true; return true }, deletionAllowed: { _, _ in false })
        let refusedResult = await refused.deleteSingleFile(item, from: .userCache)
        XCTAssertFalse(refusedResult)
        XCTAssertFalse(called)
        let allowed = SmartCleanerService(cleanupFile: { _, permanent in
            XCTAssertFalse(permanent)
            return true
        }, deletionAllowed: { _, _ in true })
        allowed.userCacheFiles = [item]
        let allowedResult = await allowed.deleteSingleFile(item, from: .userCache)
        XCTAssertTrue(allowedResult)
        XCTAssertTrue(allowed.userCacheFiles.isEmpty)
    }

    @MainActor
    func testRetryKeepsOnlyRemainingFailures() async {
        let first = CleanerFileItem(url: root.appendingPathComponent("first"), name: "first", size: 10, groupId: "cache")
        let second = CleanerFileItem(url: root.appendingPathComponent("second"), name: "second", size: 20, groupId: "cache")
        let service = SmartCleanerService(cleanupFile: { url, _ in url == first.url }, deletionAllowed: { _, _ in true })
        service.userCacheFiles = [first, second]
        let result = await service.retryFailedFiles([first, second])
        XCTAssertEqual(result.success, 1)
        XCTAssertEqual(service.lastFailedCleanupFiles.map(\.url), [second.url])
        XCTAssertEqual(service.totalMovedToTrashSize, 10)
    }
    func testExplicitLargeFileBypassStillProtectsEtc() {
        for path in ["/etc", "/etc/hosts", "/private/etc", "/private/etc/hosts",
                     "/etc/macoptimizer-nonexistent-fixture", "/private/etc/macoptimizer-nonexistent-fixture",
                     "/var/db/macoptimizer-nonexistent-fixture", "/private/var/db/macoptimizer-nonexistent-fixture",
                     "/var/root/macoptimizer-nonexistent-fixture", "/private/var/root/macoptimizer-nonexistent-fixture",
                     "/private", "/var"] {
            XCTAssertFalse(SafetyGuard.shared.isSafeToDelete(URL(fileURLWithPath: path), ignoreProtection: true), path)
        }
    }

    func testExplicitSelectionRejectsSymlinkToCoreDirectory() throws {
        let link = root.appendingPathComponent("core-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/etc"))
        XCTAssertFalse(SafetyGuard.shared.isSafeToDelete(link, ignoreProtection: true))
        XCTAssertFalse(SafetyGuard.shared.isSafeToDelete(link.appendingPathComponent("hosts"), ignoreProtection: true))
        XCTAssertTrue(SafetyGuard.shared.isSafeToDelete(URL(fileURLWithPath: "/private/etc-safe-fixture"), ignoreProtection: true))
    }

    @MainActor
    func testStoppingRetryRetainsUnattemptedFailuresWithoutDuplicateRows() async {
        let files = ["first", "second", "third"].map {
            CleanerFileItem(url: root.appendingPathComponent($0), name: $0, size: 10, groupId: "cache")
        }
        let gate = SmartCleanupTestGate()
        let service = SmartCleanerService(cleanupFile: { _, _ in
            await gate.wait()
            return true
        }, deletionAllowed: { _, _ in true })
        service.userCacheFiles = files
        let run = Task { await service.retryFailedFiles(files + [files[1]]) }
        for _ in 0..<200 {
            if await gate.hasEntered() { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let entered = await gate.hasEntered()
        XCTAssertTrue(entered)
        service.stopCleaning()
        XCTAssertTrue(service.isCleaning)
        await gate.release()
        let result = await run.value
        XCTAssertEqual(result.success, 1)
        XCTAssertEqual(result.failed, 2)
        XCTAssertEqual(service.lastFailedCleanupFiles.map(\.name), ["second", "third"])
        XCTAssertEqual(service.userCacheFiles.map(\.name), ["second", "third"])
        XCTAssertTrue(service.cleaningWasStopped)
    }

    @MainActor
    func testTaskCancellationOfRetryRetainsPendingItemsAndCancelledState() async {
        let files = ["first", "second"].map {
            CleanerFileItem(url: root.appendingPathComponent($0), name: $0, size: 10, groupId: "cache")
        }
        let gate = SmartCleanupTestGate()
        let service = SmartCleanerService(cleanupFile: { _, _ in
            await gate.wait()
            return true
        }, deletionAllowed: { _, _ in true })
        service.userCacheFiles = files
        let run = Task { await service.retryFailedFiles(files) }
        for _ in 0..<200 {
            if await gate.hasEntered() { break }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let entered = await gate.hasEntered()
        XCTAssertTrue(entered)
        run.cancel()
        await gate.release()
        let result = await run.value
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(service.lastFailedCleanupFiles.map(\.name), ["second"])
        XCTAssertTrue(service.cleaningWasStopped)
    }

}
