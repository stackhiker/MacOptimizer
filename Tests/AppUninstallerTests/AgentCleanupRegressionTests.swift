import XCTest
@testable import AppUninstaller

final class AgentCleanupRegressionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("AgentCleanup-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func oldFinding() throws -> MacAgentFinding {
        let url = root.appendingPathComponent("Library/Caches/com.fixture/old.cache")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: 10).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86400)], ofItemAtPath: url.path)
        let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return MacAgentFinding(path: url.path, category: .userCache, size: 10, modifiedAt: date)
    }

    func testChangedOrSymlinkedFindingIsNotEligibleAtCleanupTime() throws {
        let finding = try oldFinding()
        XCTAssertTrue(MacMaintenanceAgentService.isSafeCleanupFinding(finding, homeDirectory: root, permitted: { _ in true }))
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: finding.path)
        XCTAssertFalse(MacMaintenanceAgentService.isSafeCleanupFinding(finding, homeDirectory: root, permitted: { _ in true }))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-9 * 86400)], ofItemAtPath: finding.path)
        XCTAssertFalse(MacMaintenanceAgentService.isSafeCleanupFinding(finding, homeDirectory: root, permitted: { _ in true }))
        try FileManager.default.removeItem(atPath: finding.path)
        let outside = root.appendingPathComponent("personal-data")
        try Data(repeating: 42, count: 10).write(to: outside)
        try FileManager.default.createSymbolicLink(atPath: finding.path, withDestinationPath: outside.path)
        XCTAssertFalse(MacMaintenanceAgentService.isSafeCleanupFinding(finding, homeDirectory: root, permitted: { _ in true }))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testRejectedAndFailedFindingsAreCountedAndRetainedWithoutDoubleDeletion() async throws {
        let good = try oldFinding()
        let protected = MacAgentFinding(path: root.appendingPathComponent("Library/Saved Application State/state").path, category: .savedState, size: 30, modifiedAt: nil)
        let bad = MacAgentFinding(path: root.appendingPathComponent("denied").path, category: .userLog, size: 20, modifiedAt: nil)
        var deleted: [URL] = []
        var failures: [RemovalFailure] = []
        let result = await MacMaintenanceAgentService.cleanFindings([good, good, protected, bad], allowed: {
            $0.category != .savedState
        }, moveToTrash: { url in
            if url.path == bad.path { throw POSIXError(.EACCES) }
            deleted.append(url)
        }, recordFailure: { failures.append($0) })
        XCTAssertEqual(deleted.map(\.path), [good.path])
        XCTAssertEqual(result.cleanedCount, 1)
        XCTAssertEqual(result.cleanedBytes, 10)
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertEqual(result.failedPaths, Set([protected.path, bad.path]))
        XCTAssertEqual(failures.count, 2)
    }
}
