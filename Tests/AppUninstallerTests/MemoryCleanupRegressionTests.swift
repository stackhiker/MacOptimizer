import XCTest
import Darwin
@testable import AppUninstaller

final class MemoryCleanupRegressionTests: XCTestCase {
    func testOneAccountingModelIncludesCompressedButExcludesPurgeablePages() {
        let sample = MemorySnapshot(totalBytes: 1000, internalPages: 30, purgeablePages: 5,
                                    wiredPages: 10, compressedPages: 15, pageSize: 10, pressure: .warning)
        XCTAssertEqual(sample.appBytes, 250)
        XCTAssertEqual(sample.usedBytes, 500)
        XCTAssertEqual(sample.availableBytes, 500)
        XCTAssertEqual(sample.appBytes + sample.wiredBytes + sample.compressedBytes, sample.usedBytes)
        XCTAssertEqual(sample.usage, 0.5)
        let underflow = MemorySnapshot(totalBytes: 1000, internalPages: 1, purgeablePages: 2,
                                       wiredPages: 0, compressedPages: 0, pageSize: 10, pressure: .unknown)
        XCTAssertEqual(underflow.usedBytes, 0)
    }

    func testUnknownKernelPressureNeverBecomesHealthyOrCritical() {
        XCTAssertEqual(MemoryPressureLevel.fromKernelValue(UInt32(DispatchSource.MemoryPressureEvent.normal.rawValue)), .normal)
        XCTAssertEqual(MemoryPressureLevel.fromKernelValue(UInt32(DispatchSource.MemoryPressureEvent.warning.rawValue)), .warning)
        XCTAssertEqual(MemoryPressureLevel.fromKernelValue(UInt32(DispatchSource.MemoryPressureEvent.critical.rawValue)), .critical)
        XCTAssertEqual(MemoryPressureLevel.fromKernelValue(1024), .unknown)
    }

    @MainActor
    func testConfirmationDoesNotExpireIntoApproval() async {
        var waiting = true
        var checks = 0
        let allowed = await awaitExplicitMemoryConfirmation(isPresented: { waiting }, decision: { .pending }, isCancelled: { false }, wait: {
            checks += 1
            if checks == 400 { waiting = false }
        })
        XCTAssertEqual(checks, 400)
        XCTAssertFalse(allowed, "Dismissing after any elapsed time must not authorise quitting")
    }

    @MainActor
    func testExplicitConfirmationAndCancellationAreDistinct() async {
        var waiting = true
        var decision = MemoryConfirmation.pending
        let accepted = await awaitExplicitMemoryConfirmation(isPresented: { waiting }, decision: { decision }, isCancelled: { false }, wait: {
            decision = .confirmed
            waiting = false
        })
        XCTAssertTrue(accepted)
        let cancelled = await awaitExplicitMemoryConfirmation(isPresented: { false }, decision: { .confirmed }, isCancelled: { true }, wait: {})
        XCTAssertFalse(cancelled)
    }

    @MainActor
    func testUnresponsiveQuitIsRetainedWithoutAnotherTerminationRequest() async {
        var requests = 0
        var waits = 0
        let result = await requestGracefulTermination(request: { requests += 1; return true }, hasExited: { false },
            wait: { waits += 1 }, maximumChecks: 50)
        XCTAssertEqual(result, .stillRunning)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(waits, 50)
    }

    @MainActor
    func testRefusedAndCancelledQuitDoNotPretendToSucceed() async {
        var requests = 0
        let refused = await requestGracefulTermination(request: { requests += 1; return false }, hasExited: { false }, wait: {})
        XCTAssertEqual(refused, .refused)
        let cancelled = await requestGracefulTermination(request: { requests += 1; return true }, hasExited: { false }, isCancelled: { true }, wait: {})
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    func testSuccessfulQuitRequiresObservedExit() async {
        var exited = false
        let result = await requestGracefulTermination(request: { true }, hasExited: { exited }, wait: { exited = true })
        XCTAssertEqual(result, .exited)
    }

    func testCheckedCommandReportsMissingExecutableAndNonzeroExit() {
        XCTAssertFalse(runCheckedMaintenanceCommand("/nonexistent/macoptimizer-test-command", []).success)
        XCTAssertFalse(runCheckedMaintenanceCommand("/usr/bin/false", []).success)
        XCTAssertTrue(runCheckedMaintenanceCommand("/usr/bin/true", []).success)
    }
}

final class MaintenanceFileCleanupRegressionTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("maintenance-fixture-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func file(_ relative: String, old: Bool = true, accessOld: Bool = true) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 37).write(to: url)
        let oldDate = now.addingTimeInterval(-60 * 24 * 3600).timeIntervalSince1970
        var times = [timeval(tv_sec: Int(accessOld ? oldDate : now.timeIntervalSince1970), tv_usec: 0),
                     timeval(tv_sec: Int(old ? oldDate : now.timeIntervalSince1970), tv_usec: 0)]
        XCTAssertEqual(utimes(url.path, &times), 0)
        return url
    }

    func testOnlyOldRegularKnownCacheFilesOfStoppedAppsAreMoved() throws {
        let expected = try file("com.example.closed/old.cache")
        _ = try file("com.example.closed/recent.cache", old: false)
        _ = try file("com.example.closed/recent-access.cache", accessOld: false)
        _ = try file("com.example.closed/data.sqlite")
        _ = try file("com.example.running/old.cache")
        _ = try file("com.apple.system/old.cache")
        var moved: [String] = []
        let cleaner = MaintenanceFileCleaner(now: now, isOwnerRunning: { $0 == "com.example.running" }, isSafe: { _ in true }, moveToTrash: { moved.append($0.path) })
        let result = cleaner.clean(root: root, kind: .cache)
        XCTAssertEqual(moved.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }, [expected.resolvingSymlinksInPath().path])
        XCTAssertEqual(result.movedBytes, 37)
        XCTAssertEqual(result.movedCount, 1)
    }

    func testSymlinkAndHardLinkAreExcluded() throws {
        let target = try file("com.example.closed/original.cache")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("com.example.closed/link.cache"), withDestinationURL: target)
        try FileManager.default.linkItem(at: target, to: root.appendingPathComponent("com.example.closed/hard.cache"))
        var moved = 0
        let cleaner = MaintenanceFileCleaner(now: now, isSafe: { _ in true }, moveToTrash: { _ in moved += 1 })
        let result = cleaner.clean(root: root, kind: .cache)
        XCTAssertEqual(moved, 0)
        XCTAssertEqual(result.movedBytes, 0)
    }

    func testFailedMoveDoesNotCreditBytesAndCancellationDoesNotDelete() throws {
        _ = try file("com.example.closed/old.cache")
        var attempts = 0
        let cleaner = MaintenanceFileCleaner(now: now, isSafe: { _ in true }, moveToTrash: { _ in attempts += 1; throw CocoaError(.fileWriteNoPermission) })
        let failed = cleaner.clean(root: root, kind: .cache)
        XCTAssertEqual(failed.movedCount, 0)
        XCTAssertEqual(failed.movedBytes, 0)
        XCTAssertEqual(failed.failures.count, 1)
        let cancelled = cleaner.clean(root: root, kind: .cache, isCancelled: { true })
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertEqual(attempts, 1)
    }

    func testDiagnosticCleanupPreservesSavedStateContainersAndFreshReports() throws {
        let expected = try file("old.ips")
        _ = try file("recent.crash", old: false)
        _ = try file("Application.savedState/data.cache")
        _ = try file("Containers/com.example/Data/tmp/old.tmp")
        var moved: [String] = []
        let cleaner = MaintenanceFileCleaner(now: now, isSafe: { _ in true }, moveToTrash: { moved.append($0.path) })
        _ = cleaner.clean(root: root, kind: .diagnosticReports)
        XCTAssertEqual(moved.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }, [expected.resolvingSymlinksInPath().path])
    }
}

private actor MemoryServiceExecutionGate {
    private var started = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func block() async {
        started = true
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

final class MemoryServiceOwnershipRegressionTests: XCTestCase {
    @MainActor
    func testMaintenanceRejectsConcurrentBatchWithoutResettingCancellation() async {
        let gate = MemoryServiceExecutionGate()
        var invocations = 0
        let service = MaintenanceService(taskExecutor: { task in
            invocations += 1
            await gate.block()
            return TaskResult(task: task, success: true, message: "fixture", details: nil)
        })
        service.selectedTasks = [.freeRam]
        let first = Task { await service.runSelectedTasks() }
        await gate.waitUntilStarted()
        service.stopRunningTasks()
        await service.runSelectedTasks()
        XCTAssertEqual(invocations, 1)
        XCTAssertTrue(service.isRunning, "The first task still owns the batch until its worker returns")
        XCTAssertTrue(service.runWasCancelled)
        await gate.release()
        await first.value
        XCTAssertFalse(service.isRunning)
        XCTAssertTrue(service.runWasCancelled)
        XCTAssertTrue(service.completedTasks.isEmpty)
        XCTAssertFalse(service.showConfirmDialog)
        XCTAssertFalse(service.userConfirmed)
    }

    @MainActor
    func testOptimizerRejectsConcurrentBatchAndHonorsOuterTaskCancellation() async {
        let gate = MemoryServiceExecutionGate()
        var invocations = 0
        let service = OptimizerService(taskExecutor: { _ in
            invocations += 1
            await gate.block()
            return true
        })
        service.selectedTasks = [.memoryOptimize]
        let first = Task { await service.executeAllSelectedTasks() }
        await gate.waitUntilStarted()
        await service.executeAllSelectedTasks()
        XCTAssertEqual(invocations, 1)
        XCTAssertTrue(service.isExecuting)
        first.cancel()
        await gate.release()
        await first.value
        XCTAssertFalse(service.isExecuting)
        XCTAssertTrue(service.executionWasCancelled)
        XCTAssertTrue(service.completedTasks.isEmpty)
        XCTAssertFalse(service.showResults)
        XCTAssertFalse(service.showMemoryConfirmAlert)
    }

    @MainActor
    func testStoppedMaintenanceCannotBeApprovedByStaleConfirmation() async {
        var invocations = 0
        let service = MaintenanceService(taskExecutor: { task in
            invocations += 1
            return TaskResult(task: task, success: true, message: "fixture", details: nil)
        })
        service.selectedTasks = [.purgeableSpace]
        let run = Task { await service.runSelectedTasks() }
        while !service.showConfirmDialog { await Task.yield() }
        service.stopRunningTasks()
        service.confirmAction()
        XCTAssertFalse(service.userConfirmed)
        await run.value
        XCTAssertEqual(invocations, 0)
        XCTAssertTrue(service.runWasCancelled)
        XCTAssertFalse(service.showConfirmDialog)
    }
}
