import XCTest
@testable import AppUninstaller

private actor CleanupTestGate {
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var peak = 0
    func enter() async {
        calls += 1
        active += 1
        peak = max(peak, active)
        if !open { await withCheckedContinuation { waiters.append($0) } }
        active -= 1
    }
    func release() {
        open = true
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }
}

final class CleanupInfrastructureTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupInfrastructure-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func file(_ name: String, count: Int = 17) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: count).write(to: url)
        return url
    }

    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    func testLogicalSizeCountsOrdinaryFilesAndHiddenFilesWithoutFollowingLinks() throws {
        let original = try file("cache/ordinary", count: 17)
        _ = try file("cache/.hidden", count: 11)
        let outside = try file("outside", count: 99)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cache/symlink"), withDestinationURL: outside)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("cache/hardlink"))
        XCTAssertEqual(CleanupFileSystem.logicalSize(at: original), 17)
        XCTAssertEqual(CleanupFileSystem.logicalSize(at: root.appendingPathComponent("cache")), 28)
        XCTAssertEqual(CleanupFileSystem.logicalSize(at: root.appendingPathComponent("cache/symlink")), 0)
    }

    func testSizeCancellationStopsTraversalAndDoesNotPublishPartialTotal() throws {
        for index in 0..<40 { _ = try file("tree/\(index)") }
        var checks = 0
        let size = CleanupFileSystem.logicalSize(at: root.appendingPathComponent("tree")) {
            checks += 1
            return checks >= 4
        }
        XCTAssertEqual(size, 0)
        XCTAssertEqual(checks, 4)
    }

    func testUniqueRootsRemoveChildrenButKeepSimilarPrefixSiblings() {
        let urls = ["cache/file", "cache", "cache", "cache-other/file"].map { root.appendingPathComponent($0) }
        XCTAssertEqual(Set(CleanupFileSystem.uniqueRoots(urls).map(\.path)), Set([root.appendingPathComponent("cache").path, root.appendingPathComponent("cache-other/file").path]))
    }

    func testUniqueRootsStandardizesDotComponentsBeforeAncestorMatching() {
        let urls = ["cache/child", "cache/../other", "cache/./", "cache-other/file", "other/deeper"]
            .map { root.appendingPathComponent($0) }
        let expected = ["cache", "other", "cache-other/file"].map { root.appendingPathComponent($0).standardizedFileURL.path }
        XCTAssertEqual(CleanupFileSystem.uniqueRoots(urls).map(\.path), expected)
    }

    func testUniqueRootPathsHandleRootBoundariesUnicodeAndStableOrdering() {
        XCTAssertEqual(CleanupFileSystem.uniqueRootPaths([]), [])
        XCTAssertEqual(CleanupFileSystem.uniqueRootPaths(["/cache/file", "/", "/", "/cache-other"]), ["/"])
        let paths = ["/cache-long/child", "/cache/child/grandchild", "/缓存/文件", "/缓存", "/cache", "/a", "/cache"]
        XCTAssertEqual(CleanupFileSystem.uniqueRootPaths(paths), ["/a", "/缓存", "/cache", "/cache-long/child"])
        XCTAssertEqual(CleanupFileSystem.uniqueRootPaths(Array(paths.reversed())), CleanupFileSystem.uniqueRootPaths(paths))
    }

    func testUniqueRootsScaleToTwentyThousandSiblingPaths() {
        // No files are created: a large scan result should not trigger pairwise
        // URL standardization or ancestor checks during deduplication.
        let siblings = (0..<20_000).map { root.appendingPathComponent(String(format: "item-%05d", $0)) }
        let ancestor = siblings[10_000]
        let inputs = siblings + Array(siblings.prefix(500)) + [ancestor.appendingPathComponent("child"), ancestor.appendingPathComponent("child/grandchild")]
        let started = Date()
        let result = CleanupFileSystem.uniqueRoots(inputs)
        print("uniqueRoots 20,502 inputs: \(Date().timeIntervalSince(started)) seconds")
        XCTAssertEqual(result.count, siblings.count)
        XCTAssertEqual(Set(result.map(\.path)), Set(siblings.map { $0.standardizedFileURL.path }))
        XCTAssertEqual(CleanupFileSystem.uniqueRootPaths(result.map(\.path)), result.map(\.path))
    }

    func testDiskObservationCanDecreaseAndRejectsDifferentVolumes() {
        let before = CleanupDiskSnapshot(volume: 1, availableBytes: 100)
        XCTAssertEqual(CleanupDiskSnapshot(volume: 1, availableBytes: 80).change(since: before), -20)
        XCTAssertNil(CleanupDiskSnapshot(volume: 2, availableBytes: 200).change(since: before))
        XCTAssertNil(before.change(since: nil))
    }

    func testSelectionHonorsAdviceAndNeverAutomaticallySelectsPersonalFiles() {
        let cache = JunkItem(type: .userCache, path: root, size: 10)
        cache.cleanupRecommendation = CleanupAdvice(decision: .keep, confidence: 1, reason: "retain", summary: "retain")
        XCTAssertFalse(JunkCleaner.shouldSelectByDefault(cache))
        cache.cleanupRecommendation = CleanupAdvice(decision: .recommended, confidence: 1, reason: "cache", summary: "cache")
        XCTAssertTrue(JunkCleaner.shouldSelectByDefault(cache))
        let download = JunkItem(type: .downloads, path: root, size: 10)
        download.cleanupRecommendation = cache.cleanupRecommendation
        XCTAssertFalse(JunkCleaner.shouldSelectByDefault(download))
        XCTAssertFalse(download.isSelected)
        XCTAssertEqual(JunkType.userCache.searchPaths, ["~/Library/Caches"])
    }

    @MainActor
    func testLargeFileCleanupStopRetainsPendingSelections() async {
        var scanner: LargeFileScanner!
        var calls = 0
        scanner = LargeFileScanner(deleteFile: { _ in
            calls += 1
            scanner.stopCleaning()
        })
        defer { scanner = nil }
        scanner.foundFiles = ["one", "two"].map {
            FileItem(url: root.appendingPathComponent($0), name: $0, size: 10, type: "test", accessDate: Date())
        }
        scanner.selectedFiles = Set(scanner.foundFiles.map(\.id))
        let result = await scanner.deleteItems(scanner.selectedFiles)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(result.wasStopped)
        XCTAssertFalse(result.isSuccessful)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(scanner.foundFiles.count, 1)
        XCTAssertEqual(scanner.selectedFiles, Set(scanner.foundFiles.map(\.id)))
    }

    @MainActor
    func testJunkCleanupDeduplicatesAncestorsAndPreservesFailuresWithReason() async {
        let parent = JunkItem(type: .userCache, path: root.appendingPathComponent("parent"), size: 40)
        let child = JunkItem(type: .browserCache, path: parent.path.appendingPathComponent("child"), size: 20)
        let denied = JunkItem(type: .systemCache, path: root.appendingPathComponent("denied"), size: 30)
        let keep = JunkItem(type: .downloads, path: root.appendingPathComponent("keep"), size: 99)
        let cleaner = JunkCleaner(deleteFile: { url in
            if url.lastPathComponent == "denied" { throw POSIXError(.EACCES) }
        }, deletionAllowed: { _, _ in true }, recordFailure: { _ in })
        cleaner.junkItems = [child, parent, denied, keep]
        let result = await cleaner.cleanSelectedByCategory()
        XCTAssertEqual(result.cleaned, 40)
        XCTAssertEqual(result.failed, 30)
        XCTAssertEqual(Set(cleaner.junkItems.map(\.id)), Set([denied.id, keep.id]))
        XCTAssertEqual(cleaner.deletionFailures.count, 1)
        XCTAssertEqual(cleaner.deletionFailures.first?.errorCode, Int(EACCES))
        XCTAssertFalse(cleaner.isCleaning)
    }

    @MainActor
    func testJunkCleanupStopKeepsOwnershipAndLeavesPendingFiles() async {
        let gate = CleanupTestGate()
        let cleaner = JunkCleaner(deleteFile: { _ in await gate.enter() }, deletionAllowed: { _, _ in true }, recordFailure: { _ in })
        cleaner.junkItems = ["one", "two"].map { JunkItem(type: .userCache, path: root.appendingPathComponent($0), size: 10) }
        let run = Task { await cleaner.cleanSelectedByCategory() }
        let entered = await waitUntil { await gate.calls == 1 }
        XCTAssertTrue(entered)
        cleaner.stopCleaning()
        XCTAssertTrue(cleaner.isCleaning)
        let overlap = await cleaner.cleanSelectedByCategory()
        XCTAssertEqual(overlap.cleaned, 0)
        await gate.release()
        let result = await run.value
        XCTAssertEqual(result.cleaned, 10)
        XCTAssertEqual(cleaner.junkItems.count, 1)
        XCTAssertTrue(cleaner.junkItems[0].isSelected)
    }

    @MainActor
    func testJunkScanCancellationIsBoundedAndCannotPublishOldResultsOrRestartEarly() async {
        let gate = CleanupTestGate()
        let path = root.appendingPathComponent("fixture")
        let cleaner = JunkCleaner(scanType: { type in
            await gate.enter()
            return ([JunkItem(type: type, path: path, size: 10)], false)
        })
        let scan = Task { await cleaner.scanJunk() }
        let entered = await waitUntil { await gate.calls == 4 }
        XCTAssertTrue(entered)
        cleaner.stopScanning()
        XCTAssertTrue(cleaner.isScanning)
        await cleaner.scanJunk()
        let calls = await gate.calls
        XCTAssertEqual(calls, 4)
        await gate.release()
        await scan.value
        XCTAssertTrue(cleaner.junkItems.isEmpty)
        XCTAssertFalse(cleaner.isScanning)
        await cleaner.scanJunk()
        XCTAssertEqual(cleaner.junkItems.count, 1)
        let peak = await gate.peak
        XCTAssertLessThanOrEqual(peak, 4)
    }
}
