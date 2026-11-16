import XCTest
import AppKit
@testable import AppUninstaller

private actor DeepCleanGate {
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

private actor DeepCleanProbe {
    private(set) var calls = 0
    private(set) var paths: [URL] = []
    private(set) var active = 0
    private(set) var peak = 0
    func record(_ path: URL? = nil) {
        calls += 1
        if let path { paths.append(path) }
    }
    func enter() { active += 1; peak = max(peak, active) }
    func leave() { active -= 1 }
}

final class DeepCleanRegressionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DeepCleanRegression-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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

    @MainActor
    func testStopRetainsScanOwnershipUntilWorkerExitsAndDropsLateResults() async {
        let gate = DeepCleanGate()
        let probe = DeepCleanProbe()
        let item = DeepCleanItem(url: root.appendingPathComponent("late-cache"), name: "late", size: 20, category: .junkFiles)
        let scanner = DeepCleanScanner(scanCategory: { category in
            if category == .junkFiles {
                await probe.record()
                await gate.wait()
                return [item]
            }
            return []
        })
        let first = Task { await scanner.startScan() }
        let entered = await waitUntil { await probe.calls == 1 }
        XCTAssertTrue(entered)
        scanner.stopScan()
        XCTAssertTrue(scanner.isScanning)
        XCTAssertTrue(scanner.isStoppingScan)
        await scanner.startScan()
        let rejectedCleanup = await scanner.cleanSelected()
        XCTAssertTrue(rejectedCleanup.wasStopped)
        let callsBeforeExit = await probe.calls
        XCTAssertEqual(callsBeforeExit, 1)
        await gate.open()
        await first.value
        XCTAssertFalse(scanner.isScanning)
        XCTAssertTrue(scanner.scanWasStopped)
        XCTAssertTrue(scanner.items.isEmpty, "A cancelled category must not publish late results")
        await scanner.startScan()
        XCTAssertFalse(scanner.scanWasStopped)
        XCTAssertEqual(scanner.items.count, 1)
        XCTAssertEqual(scanner.totalSize, 20)
    }

    @MainActor
    func testParentTaskCancellationAlsoStopsOwnedScan() async {
        let gate = DeepCleanGate()
        let probe = DeepCleanProbe()
        let item = DeepCleanItem(url: root.appendingPathComponent("late"), name: "late", size: 10, category: .junkFiles)
        let scanner = DeepCleanScanner(scanCategory: { _ in
            await probe.record()
            await gate.wait()
            return [item]
        })
        let task = Task { await scanner.startScan() }
        let entered = await waitUntil { await probe.calls > 0 }
        XCTAssertTrue(entered)
        task.cancel()
        await gate.open()
        await task.value
        XCTAssertTrue(scanner.scanWasStopped)
        XCTAssertFalse(scanner.isScanning)
        XCTAssertTrue(scanner.items.isEmpty)
    }

    @MainActor
    func testScanDeduplicatesParentsAndPathsAcrossCategoriesBeforeTotals() async {
        let parent = root.appendingPathComponent("cache")
        let child = parent.appendingPathComponent("sub/file")
        let scanner = DeepCleanScanner(scanCategory: { category in
            switch category {
            case .junkFiles:
                return [DeepCleanItem(url: child, name: "child", size: 40, category: category)]
            case .systemCaches:
                return [DeepCleanItem(url: parent, name: "cache", size: 100, category: category),
                        DeepCleanItem(url: parent, name: "duplicate", size: 100, category: category)]
            default: return []
            }
        })
        await scanner.startScan()
        XCTAssertEqual(scanner.items.count, 1)
        XCTAssertEqual(scanner.totalSize, 100)
        XCTAssertEqual(scanner.selectedSize, 100)
    }

    @MainActor
    func testCleanupRetainsFailuresAndUnselectedItemsWithOriginalError() async {
        let good = root.appendingPathComponent("cache")
        let child = good.appendingPathComponent("child")
        let denied = root.appendingPathComponent("denied")
        let keep = root.appendingPathComponent("keep")
        let probe = DeepCleanProbe()
        var recordedFailures: [RemovalFailure] = []
        let scanner = DeepCleanScanner(trashItem: { url in
            await probe.record(url)
            if url == denied { throw CocoaError(.fileWriteNoPermission) }
        }, deletionAllowed: { _, _ in true }, recordFailure: { recordedFailures.append($0) })
        scanner.items = [
            DeepCleanItem(url: good, name: "cache", size: 100, category: .junkFiles),
            DeepCleanItem(url: child, name: "child", size: 30, category: .systemCaches),
            DeepCleanItem(url: good, name: "duplicate", size: 100, category: .systemCaches),
            DeepCleanItem(url: denied, name: "denied", size: 20, category: .junkFiles),
            DeepCleanItem(url: keep, name: "keep", size: 40, category: .junkFiles, isSelected: false)
        ]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.size, 100)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.failures.first?.path, denied)
        XCTAssertEqual(result.failures.first?.errorDomain, NSCocoaErrorDomain)
        XCTAssertEqual(result.failures.first?.errorCode, NSFileWriteNoPermissionError)
        XCTAssertEqual(recordedFailures.count, 1)
        XCTAssertEqual(Set(scanner.items.map(\.url)), Set([denied, keep]))
        XCTAssertEqual(scanner.totalSize, 60)
        XCTAssertFalse(scanner.isCleaning)
        let attempted = await probe.paths
        XCTAssertEqual(Set(attempted), Set([good, denied]))
        XCTAssertEqual(attempted.count, 2)
    }

    @MainActor
    func testProtectedItemIsNotPassedToTrashAndReportsReason() async {
        let probe = DeepCleanProbe()
        let scanner = DeepCleanScanner(trashItem: { await probe.record($0) },
                                       deletionAllowed: { _, _ in false }, recordFailure: { _ in })
        scanner.items = [DeepCleanItem(url: root.appendingPathComponent("protected"), name: "protected", size: 4, category: .junkFiles)]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.failures.first?.errorDomain, "MacOptimizer.CleanupSafety")
        XCTAssertEqual(scanner.items.count, 1)
        let attempts = await probe.calls
        XCTAssertEqual(attempts, 0)
    }

    func testPersonalFilesAndInferredResidualsStartUnselected() {
        for category in [DeepCleanCategory.largeFiles, .appResiduals] {
            XCTAssertFalse(DeepCleanItem(url: root, name: "review", size: 1, category: category).isSelected)
        }
    }

    func testConcurrentTraversalHonorsLimitAndExcludesSymlinkTargets() async throws {
        var directories: [URL] = []
        for index in 0..<5 {
            let directory = root.appendingPathComponent("dir\(index)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1]).write(to: directory.appendingPathComponent("file"))
            directories.append(directory)
        }
        try FileManager.default.createSymbolicLink(at: directories[0].appendingPathComponent("link"), withDestinationURL: directories[1].appendingPathComponent("file"))
        let probe = DeepCleanProbe()
        let files = await scanDirectoryConcurrently(directories: directories,
            configuration: ScanConfiguration(maxConcurrency: 2)) { url, _ in
                await probe.enter()
                try? await Task.sleep(nanoseconds: 5_000_000)
                await probe.leave()
                return url
            }
        XCTAssertEqual(files.count, 5)
        let peak = await probe.peak
        XCTAssertLessThanOrEqual(peak, 2)
        XCTAssertGreaterThan(peak, 0)
    }
}
