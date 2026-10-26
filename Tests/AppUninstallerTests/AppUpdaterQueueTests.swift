import XCTest
@testable import AppUninstaller

private actor UpdateQueueProbe {
    private var active = 0
    private var maximum = 0
    private var order: [String] = []

    func enter(_ id: String) {
        active += 1
        maximum = max(maximum, active)
        order.append(id)
    }

    func leave() { active -= 1 }
    func result() -> (maximum: Int, order: [String]) { (maximum, order) }
}

final class AppUpdaterQueueTests: XCTestCase {
    func testGateBoundsParallelWork() async {
        let gate = AppUpdateConcurrencyGate(limit: 3)
        let probe = UpdateQueueProbe()

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<9 {
                group.addTask {
                    let id = "update-\(index)"
                    do {
                        try await gate.acquire(id)
                        await probe.enter(id)
                        try await Task.sleep(nanoseconds: 20_000_000)
                        await probe.leave()
                        await gate.release(id)
                    } catch {
                        XCTFail("Unexpected queue failure: \(error)")
                    }
                }
            }
        }

        let result = await probe.result()
        XCTAssertEqual(result.maximum, 3)
        XCTAssertEqual(result.order.count, 9)
        let final = await gate.snapshot()
        XCTAssertTrue(final.active.isEmpty)
        XCTAssertTrue(final.queued.isEmpty)
    }

    func testGateStartsWaitingUpdatesInFIFOOrder() async throws {
        let gate = AppUpdateConcurrencyGate(limit: 1)
        let probe = UpdateQueueProbe()
        try await gate.acquire("holder")

        let second = Task {
            try await gate.acquire("second")
            await probe.enter("second")
            await gate.release("second")
        }
        await waitForQueue(["second"], gate: gate)

        let third = Task {
            try await gate.acquire("third")
            await probe.enter("third")
            await gate.release("third")
        }
        await waitForQueue(["second", "third"], gate: gate)

        await gate.release("holder")
        try await second.value
        try await third.value
        let result = await probe.result()
        XCTAssertEqual(result.order, ["second", "third"])
    }

    func testCancellingWaitingUpdateDoesNotConsumePermit() async throws {
        let gate = AppUpdateConcurrencyGate(limit: 1)
        try await gate.acquire("holder")
        let waiting = Task { try await gate.acquire("cancelled") }
        await waitForQueue(["cancelled"], gate: gate)

        waiting.cancel()
        do {
            try await waiting.value
            XCTFail("Cancelled waiter unexpectedly acquired a permit")
        } catch is CancellationError {
            // Expected.
        }

        await gate.release("holder")
        try await gate.acquire("next")
        let snapshot = await gate.snapshot()
        XCTAssertEqual(snapshot.active, Set(["next"]))
        XCTAssertTrue(snapshot.queued.isEmpty)
        await gate.release("next")
    }

    private func waitForQueue(_ expected: [String], gate: AppUpdateConcurrencyGate) async {
        for _ in 0..<200 {
            if await gate.snapshot().queued == expected { return }
            await Task.yield()
        }
        XCTFail("Queue did not reach expected state: \(expected)")
    }
}
