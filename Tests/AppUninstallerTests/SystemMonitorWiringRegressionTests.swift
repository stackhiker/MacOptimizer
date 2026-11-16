import XCTest
@testable import AppUninstaller

final class SystemMonitorWiringRegressionTests: XCTestCase {
    @MainActor
    func testMonitoringUpdatesMemoryNetworkAndConnectionDuration() async throws {
        let monitor = SystemMonitorService()
        monitor.memoryTotalString = "pending"
        monitor.totalDownload = "pending"
        monitor.connectionDuration = "pending"
        let client = "monitor-wiring-regression"
        monitor.startMonitoring(client: client)
        defer { monitor.stopMonitoring(client: client) }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if monitor.memoryTotalString != "pending",
               monitor.totalDownload != "pending",
               monitor.connectionDuration != "pending" { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotEqual(monitor.memoryTotalString, "pending", "The public monitoring lifecycle must publish memory samples")
        XCTAssertNotEqual(monitor.totalDownload, "pending", "The public monitoring lifecycle must publish network samples")
        XCTAssertNotEqual(monitor.connectionDuration, "pending", "Non-memory monitoring must remain wired after memory changes")
    }
    @MainActor
    func testNetworkScopeDoesNotSampleMemoryAndCanSwitchToOverview() async throws {
        let monitor = SystemMonitorService()
        monitor.memoryTotalString = "pending"
        monitor.totalDownload = "pending"
        monitor.startMonitoring(client: "scope-test", scope: .network)
        defer { monitor.stopMonitoring(client: "scope-test") }
        for _ in 0..<100 where monitor.totalDownload == "pending" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNotEqual(monitor.totalDownload, "pending")
        XCTAssertEqual(monitor.memoryTotalString, "pending")
        monitor.startMonitoring(client: "scope-test", scope: .overview)
        for _ in 0..<200 where monitor.memoryTotalString == "pending" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertNotEqual(monitor.memoryTotalString, "pending")
    }
}
