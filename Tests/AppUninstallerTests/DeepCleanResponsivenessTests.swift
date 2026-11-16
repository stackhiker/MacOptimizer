import XCTest
import AppKit
@testable import AppUninstaller

private final class DeepCleanMergePause: @unchecked Sendable {
    let entered: XCTestExpectation
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let pauseAt: Int
    private var calls = 0
    private var usedMainThread = false

    init(pauseAt: Int = 1, entered: XCTestExpectation) {
        self.pauseAt = pauseAt
        self.entered = entered
    }

    func select(_ paths: [String]) -> [String] {
        lock.lock()
        calls += 1
        usedMainThread = usedMainThread || Thread.isMainThread
        let shouldPause = calls == pauseAt
        lock.unlock()
        if shouldPause {
            entered.fulfill()
            _ = release.wait(timeout: .now() + 5)
        }
        return CleanupFileSystem.uniqueRootPaths(paths)
    }

    var ranOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return usedMainThread
    }
}

final class DeepCleanResponsivenessTests: XCTestCase {
    @MainActor
    func testRepeatedSummaryReadsReuseCacheAndSelectionChangesInvalidateIt() {
        let scanner = DeepCleanScanner()
        let parent = URL(fileURLWithPath: "/private/tmp/deep-clean-summary/cache")
        scanner.items = [
            DeepCleanItem(url: parent, name: "parent", size: 100, category: .systemCaches),
            DeepCleanItem(url: parent.appendingPathComponent("child"), name: "child", size: 40, category: .systemCaches),
            DeepCleanItem(url: parent, name: "duplicate", size: 100, category: .systemCaches),
            DeepCleanItem(url: URL(fileURLWithPath: "/private/tmp/deep-clean-summary/cache-other"),
                          name: "sibling", size: 20, category: .systemLogs)
        ]
        XCTAssertEqual(scanner.selectedSize, 120)
        XCTAssertEqual(scanner.selectedCount, 2)
        let builds = scanner.selectedSummaryBuildCount
        for _ in 0..<10_000 {
            XCTAssertEqual(scanner.selectedSize, 120)
            XCTAssertEqual(scanner.selectedCount, 2)
        }
        XCTAssertEqual(scanner.selectedSummaryBuildCount, builds)

        scanner.items[0].isSelected = false
        scanner.items[2].isSelected = false
        XCTAssertEqual(scanner.selectedSize, 60, "Selecting only the child must count the child")
        XCTAssertEqual(scanner.selectedCount, 2)
        XCTAssertEqual(scanner.selectedSummaryBuildCount, builds + 1)
        scanner.toggleCategorySelection(.systemCaches, to: false)
        XCTAssertEqual(scanner.selectedSize, 20)
        XCTAssertEqual(scanner.selectedCount, 1)
        scanner.items.removeAll()
        XCTAssertEqual(scanner.selectedSize, 0)
        XCTAssertEqual(scanner.selectedCount, 0)
    }

    @MainActor
    func testDisplayUsesScannedPathsButCleanupResolvesAndRevalidatesLivePaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeepCleanPaths-\(UUID().uuidString)")
        let original = root.appendingPathComponent("original")
        let replacement = root.appendingPathComponent("replacement")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        defer { try? FileManager.default.removeItem(at: root) }

        var checkedPaths: [String] = []
        var trashCalls = 0
        let scanner = DeepCleanScanner(trashItem: { _ in trashCalls += 1 }, deletionAllowed: { url, _ in
            checkedPaths.append(url.standardizedFileURL.resolvingSymlinksInPath().path)
            return false
        }, recordFailure: { _ in })
        scanner.items = [
            DeepCleanItem(url: alias, name: "alias", size: 100, category: .systemCaches),
            DeepCleanItem(url: original.appendingPathComponent("child"), name: "child", size: 40, category: .systemCaches)
        ]
        XCTAssertEqual(scanner.selectedSize, 100)
        XCTAssertEqual(scanner.selectedCount, 1)

        try FileManager.default.removeItem(at: alias)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: replacement)
        // Invalidate the summary without changing its scan-time paths.
        scanner.items[0].isSelected = true
        XCTAssertEqual(scanner.selectedSize, 100)
        XCTAssertEqual(scanner.selectedCount, 1)

        let result = await scanner.cleanSelected()
        XCTAssertEqual(result.failures.count, 2, "Live paths now refer to two distinct roots")
        XCTAssertTrue(checkedPaths.contains(replacement.standardizedFileURL.resolvingSymlinksInPath().path))
        XCTAssertEqual(trashCalls, 0, "The cached display summary must never authorize deletion")
    }

    @MainActor
    func testCancellingBackgroundMergeDropsItsResult() async {
        let pause = DeepCleanMergePause(entered: expectation(description: "Background merge started"))
        let item = DeepCleanItem(url: URL(fileURLWithPath: "/private/tmp/deep-clean-cancel/cache"),
                                 name: "cache", size: 100, category: .systemCaches)
        let scanner = DeepCleanScanner(scanCategory: { _ in [item] }, scanRootSelector: { pause.select($0) })
        let scan = Task { await scanner.startScan() }
        await fulfillment(of: [pause.entered], timeout: 3)
        scanner.stopScan()
        XCTAssertTrue(scanner.isScanning)
        pause.release.signal()
        await scan.value
        XCTAssertFalse(pause.ranOnMainThread)
        XCTAssertTrue(scanner.scanWasStopped)
        XCTAssertTrue(scanner.items.isEmpty)
        XCTAssertTrue(scanner.completedCategories.isEmpty)
    }

    @MainActor
    func testBackgroundMergeDoesNotOverwriteChangedSelection() async {
        let pause = DeepCleanMergePause(pauseAt: 2, entered: expectation(description: "Second merge started"))
        let item = DeepCleanItem(url: URL(fileURLWithPath: "/private/tmp/deep-clean-selection/cache"),
                                 name: "cache", size: 100, category: .junkFiles)
        let scanner = DeepCleanScanner(scanCategory: { $0 == .junkFiles ? [item] : [] },
                                       scanRootSelector: { pause.select($0) })
        let scan = Task { await scanner.startScan() }
        await fulfillment(of: [pause.entered], timeout: 3)
        XCTAssertEqual(scanner.items.count, 1)
        scanner.items[0].isSelected = false
        pause.release.signal()
        await scan.value
        XCTAssertFalse(pause.ranOnMainThread)
        XCTAssertEqual(scanner.items.count, 1)
        XCTAssertFalse(scanner.items[0].isSelected)
        XCTAssertEqual(scanner.totalSize, 100)
        XCTAssertEqual(scanner.selectedSize, 0)
        XCTAssertEqual(scanner.completedCategories.count, DeepCleanCategory.allCases.count)
    }
}
