import AppKit
import Foundation
import XCTest
@testable import AppUninstaller

final class SmartCleanerResponsivenessTests: XCTestCase {
    private func item(_ path: String, size: Int64 = 10, selected: Bool = true) -> CleanerFileItem {
        CleanerFileItem(
            url: URL(fileURLWithPath: "/private/tmp/smart-cleaner-display-fixture/" + path),
            name: path, size: size, groupId: "example.app", isDirectory: false, isSelected: selected
        )
    }

    @MainActor
    func testCachedTotalsDeduplicateSelectedParentsAndUpdateAfterSelectionChanges() {
        let service = SmartCleanerService()
        let parent = item("cache", size: 100)
        let child = item("cache/child", size: 30)
        service.systemCacheFiles = [child]
        service.userCacheFiles = [parent, parent]
        XCTAssertEqual(service.systemJunkTotalSize, 100)
        XCTAssertEqual(service.sizeFor(category: .userCache), 100)

        service.toggleCategorySelection(.userCache, forceTo: false)
        XCTAssertEqual(service.systemJunkTotalSize, 30)
        service.toggleFileSelection(file: child, in: .systemCache)
        XCTAssertEqual(service.systemJunkTotalSize, 0)
        XCTAssertTrue(service.hasJunkResults, "Unselecting results must not return the page to its initial state")

        service.toggleMainCategorySelection(.systemJunk)
        XCTAssertEqual(service.systemJunkTotalSize, 100)
        service.resetAll()
        XCTAssertEqual(service.systemJunkTotalSize, 0)
        XCTAssertFalse(service.hasJunkResults)
    }

    @MainActor
    func testGroupedFileEditsRefreshTotalsAndRemovedGroupsCannotInvalidateThem() {
        let service = SmartCleanerService()
        let group = AppCacheGroup(appName: "Example", bundleId: "example.app", icon: NSImage(), files: [item("group/a")])
        service.appCacheGroups = [group]
        XCTAssertEqual(service.systemJunkTotalSize, 10)
        group.files[0].isSelected = false
        XCTAssertEqual(service.systemJunkTotalSize, 0)
        group.files.append(item("group/b", size: 20))
        XCTAssertEqual(service.sizeFor(category: .userCache), 20)
        service.toggleAppGroupSelection(group)
        XCTAssertEqual(service.systemJunkTotalSize, 30)
        service.deselectFiles(for: "example.app")
        XCTAssertEqual(service.systemJunkTotalSize, 0)
        service.appCacheGroups = []
        let builds = service.junkSummaryBuildCount
        group.files.append(item("orphan"))
        XCTAssertEqual(service.junkSummaryBuildCount, builds)
        XCTAssertFalse(service.hasJunkResults)
    }

    @MainActor
    func testRepeatedDisplayReadsDoNotRebuildLargeResultAccounting() {
        let service = SmartCleanerService()
        service.userCacheFiles = (0..<5_000).map { item("siblings/file-\($0)", size: 3) }
        let builds = service.junkSummaryBuildCount
        for _ in 0..<1_000 {
            XCTAssertEqual(service.systemJunkTotalSize, 15_000)
            XCTAssertEqual(service.sizeFor(category: .userCache), 15_000)
            XCTAssertEqual(service.countFor(category: .systemJunk), 5_000)
            XCTAssertTrue(service.hasJunkResults)
        }
        XCTAssertEqual(service.junkSummaryBuildCount, builds)

        service.toggleCategorySelection(.userCache, forceTo: false)
        XCTAssertEqual(service.junkSummaryBuildCount, builds + 1, "Bulk selection must publish one rebuilt summary, not one per file")
        XCTAssertEqual(service.systemJunkTotalSize, 0)
    }

    @MainActor
    func testDisplayAccountingKeepsScanIdentityWhenFilesystemAliasesChange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let alias = root.appendingPathComponent("alias")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        let service = SmartCleanerService()
        service.userCacheFiles = [
            CleanerFileItem(url: alias, name: "alias", size: 10, groupId: "cache", isDirectory: false),
            CleanerFileItem(url: second, name: "second", size: 20, groupId: "cache", isDirectory: false)
        ]
        XCTAssertEqual(service.systemJunkTotalSize, 30)
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: second)
        XCTAssertEqual(service.systemJunkTotalSize, 30, "Rendering must not re-resolve paths; cleanup independently rechecks live paths")
        XCTAssertEqual(SmartCleanerService.uniqueFiles(service.userCacheFiles).count, 1, "Cleanup still uses fresh canonical identities")
    }

    @MainActor
    func testResultReconciliationRunsOnWorkerAndPreservesParentPrecedence() async {
        let gate = SmartJunkRootGate(block: false)
        let service = SmartCleanerService(junkRootSelector: { gate.select($0) })
        let parent = item("parent", size: 100)
        service.systemCacheFiles = [item("parent/child", size: 30)]
        service.userCacheFiles = [parent, parent]
        await service.deduplicateJunkResults()
        XCTAssertTrue(gate.started)
        XCTAssertFalse(gate.ranOnMainThread)
        XCTAssertTrue(service.systemCacheFiles.isEmpty)
        XCTAssertEqual(service.userCacheFiles.count, 1)
        XCTAssertEqual(service.systemJunkTotalSize, 100)
    }

    @MainActor
    func testRunningAppDeselectionMatchesBundleIDInOriginalAliasPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("actual-cache")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let alias = root.appendingPathComponent("com.example.active-cache")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: destination)
        try Data([1]).write(to: destination.appendingPathComponent("entry"))
        let aliased = CleanerFileItem(
            url: alias.appendingPathComponent("entry"), name: "entry", size: 10,
            groupId: "cache", isDirectory: false
        )
        XCTAssertFalse(aliased.canonicalPath.contains("com.example.active"))
        let group = AppCacheGroup(appName: "Unknown", bundleId: nil, icon: NSImage(), files: [aliased])
        let service = SmartCleanerService()
        service.userCacheFiles = [aliased, item("unrelated", size: 20)]
        service.appCacheGroups = [group]

        service.deselectFiles(for: "com.example.active")

        XCTAssertFalse(service.userCacheFiles[0].isSelected)
        XCTAssertFalse(group.files[0].isSelected)
        XCTAssertTrue(service.userCacheFiles[1].isSelected)
        XCTAssertEqual(service.systemJunkTotalSize, 20)
    }

    @MainActor
    func testStaleReconciliationCannotOverwriteNewResults() async {
        let gate = SmartJunkRootGate(block: true)
        let service = SmartCleanerService(junkRootSelector: { gate.select($0) })
        let old = item("old")
        service.userCacheFiles = [old, old]
        let operation = Task { await service.deduplicateJunkResults() }
        await waitForWorker(gate)
        service.userCacheFiles = [item("replacement", size: 42)]
        gate.release()
        await operation.value
        XCTAssertEqual(service.userCacheFiles.map(\.name), ["replacement"])
        XCTAssertEqual(service.systemJunkTotalSize, 42)
    }

    @MainActor
    func testCancelledReconciliationDoesNotPublishItsResult() async {
        let gate = SmartJunkRootGate(block: true)
        let service = SmartCleanerService(junkRootSelector: { gate.select($0) })
        let file = item("retained")
        service.userCacheFiles = [file, file]
        let operation = Task { await service.deduplicateJunkResults() }
        await waitForWorker(gate)
        operation.cancel()
        gate.release()
        await operation.value
        XCTAssertEqual(service.userCacheFiles.count, 2)
        XCTAssertEqual(service.systemJunkTotalSize, 10)
    }

    @MainActor
    private func waitForWorker(_ gate: SmartJunkRootGate) async {
        for _ in 0..<500 {
            if gate.started { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Background reconciliation did not start")
    }
}

private final class SmartJunkRootGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let block: Bool
    private var didStart = false
    private var usedMainThread = false

    init(block: Bool) { self.block = block }

    var started: Bool {
        lock.lock(); defer { lock.unlock() }
        return didStart
    }

    var ranOnMainThread: Bool {
        lock.lock(); defer { lock.unlock() }
        return usedMainThread
    }

    func select(_ paths: [String]) -> [String] {
        lock.lock()
        didStart = true
        usedMainThread = Thread.isMainThread
        lock.unlock()
        if block { _ = semaphore.wait(timeout: .now() + 5) }
        return CleanupFileSystem.uniqueRootPaths(paths)
    }

    func release() { semaphore.signal() }
}
