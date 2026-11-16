import XCTest
import CryptoKit
@testable import AppUninstaller

final class AgentCancellationRegressionTests: XCTestCase {
    func testHashCancellationDoesNotReturnPartialDigest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHash-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.bin")
        let bytes = Data(repeating: 42, count: 3 * 1_048_576)
        try bytes.write(to: file)
        let full = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(MacMaintenanceAgentService.sha256(of: file), full)
        var checks = 0
        let cancelled = MacMaintenanceAgentService.sha256(of: file, shouldCancel: {
            checks += 1
            return checks >= 3
        })
        XCTAssertNil(cancelled)
        XCTAssertGreaterThanOrEqual(checks, 3)
    }

    func testCancelledDuplicateScanDoesNotExposePartialDeletionCandidates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AgentDuplicates-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 9, count: 2048).write(to: root.appendingPathComponent("a"))
        try Data(repeating: 9, count: 2048).write(to: root.appendingPathComponent("b"))
        let report = MacMaintenanceAgentService.duplicateReport(in: [root], shouldCancel: { true })
        XCTAssertEqual(report.facts["state"], "cancelled")
        XCTAssertTrue(report.findings.isEmpty)
    }
    @MainActor func testCancelledCleanupRetainsUnattemptedItemsWithoutFailureJournalSpam() async {
        let findings = (0..<20).map { index in
            MacAgentFinding(path: "/private/tmp/never-deleted-fixture-\(index)", category: .userCache,
                size: 10, modifiedAt: nil)
        }
        var attempts = 0
        var loggedFailures = 0
        let task = Task {
            await MacMaintenanceAgentService.cleanFindings(findings, allowed: { _ in true },
                moveToTrash: { _ in attempts += 1 }, recordFailure: { _ in loggedFailures += 1 })
        }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(loggedFailures, 0)
        XCTAssertEqual(result.cleanedCount, 0)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertTrue(result.failedPaths.isEmpty)
        XCTAssertEqual(result.unprocessedPaths, Set(findings.map(\.path)))
    }

}
