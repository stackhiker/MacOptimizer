import Foundation
import XCTest
@testable import AppUninstaller

final class SmartInstallationResidueTests: XCTestCase {
    @MainActor
    func testDiscoveredResidueRemainsVisibleButUnselected() async throws {
        let fixture = try ResidueFixture()
        defer { fixture.remove() }
        let candidate = try await fixture.candidate()
        var deleted = false
        let service = SmartCleanerService(cleanupFile: { _, _ in deleted = true; return true },
                                          installationResidueScan: { [candidate] })
        service.oldUpdateFiles = await service.scanInstallationResidues()

        XCTAssertEqual(service.filesFor(category: .oldUpdates).count, 1)
        XCTAssertEqual(service.countFor(category: .oldUpdates), 1)
        XCTAssertTrue(service.hasJunkResults)
        XCTAssertFalse(try XCTUnwrap(service.oldUpdateFiles.first).isSelected)
        XCTAssertEqual(service.systemJunkTotalSize, 0)
        let result = await service.cleanAll()
        XCTAssertEqual(result.success, 0)
        XCTAssertFalse(deleted)
        XCTAssertEqual(service.oldUpdateFiles.count, 1)
    }

    @MainActor
    func testExplicitSelectionValidatesFreshBeforeMovingToTrash() async throws {
        let fixture = try ResidueFixture()
        defer { fixture.remove() }
        let candidate = try await fixture.candidate()
        var events: [String] = []
        let service = SmartCleanerService(cleanupFile: { url, permanent in
            XCTAssertEqual(url, candidate.url)
            XCTAssertFalse(permanent)
            events.append("trash")
            return true
        }, deletionAllowed: { _, _ in
            XCTFail("Residues use the narrow validated safety gate, never a generic bypass")
            return false
        }, installationResidueScan: { [candidate] }, installationResidueValidator: { value in
            events.append("validate")
            return await fixture.scanner.validateForRemoval(value)
        })
        service.oldUpdateFiles = await service.scanInstallationResidues()
        service.toggleCategorySelection(.oldUpdates, forceTo: true)
        XCTAssertEqual(service.systemJunkTotalSize, candidate.size)

        let result = await service.cleanAll()

        XCTAssertEqual(events, ["validate", "trash"])
        XCTAssertEqual(result.success, 1)
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(service.oldUpdateFiles.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.payload.path), "The test's cleanup hook never deletes files")
    }

    @MainActor
    func testChangedCandidateIsRetainedAndRetryChecksAgain() async throws {
        let fixture = try ResidueFixture()
        defer { fixture.remove() }
        let candidate = try await fixture.candidate()
        var validations = 0
        let service = SmartCleanerService(cleanupFile: { _, _ in
            XCTFail("A changed installation directory must be retained")
            return true
        }, installationResidueScan: { [candidate] }, installationResidueValidator: { value in
            validations += 1
            return await fixture.scanner.validateForRemoval(value)
        })
        service.oldUpdateFiles = await service.scanInstallationResidues()
        service.toggleCategorySelection(.oldUpdates, forceTo: true)
        try Data(repeating: 2, count: 31).write(to: fixture.payload)

        let result = await service.cleanAll()
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.success, 0)
        XCTAssertEqual(service.oldUpdateFiles.count, 1)
        let retry = await service.retryFailedFiles(result.failedFiles)
        XCTAssertEqual(retry.failed, 1)
        XCTAssertEqual(validations, 2)
        XCTAssertEqual(service.lastFailedCleanupFiles.count, 1)
    }

    @MainActor
    func testCandidateThatBecomesActiveAfterScanIsRetained() async throws {
        let activity = ResidueActivityProbe()
        let fixture = try ResidueFixture(activity: activity)
        defer { fixture.remove() }
        let candidate = try await fixture.candidate()
        let service = SmartCleanerService(cleanupFile: { _, _ in
            XCTFail("An installation directory now in use must be retained")
            return true
        }, installationResidueScan: { [candidate] }, installationResidueValidator: { value in
            await fixture.scanner.validateForRemoval(value)
        })
        service.oldUpdateFiles = await service.scanInstallationResidues()
        service.toggleCategorySelection(.oldUpdates, forceTo: true)
        activity.setActivePaths([fixture.payload.path])

        let result = await service.cleanAll()
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(service.oldUpdateFiles.count, 1)
    }

    @MainActor
    func testOldUpdatesLabelAloneDoesNotBypassOrdinarySafety() async throws {
        let fixture = try ResidueFixture()
        defer { fixture.remove() }
        var checkedOrdinaryGate = false
        let service = SmartCleanerService(cleanupFile: { _, _ in
            XCTFail("The ordinary safety gate refused this item")
            return true
        }, deletionAllowed: { _, ignoreProtection in
            XCTAssertFalse(ignoreProtection)
            checkedOrdinaryGate = true
            return false
        }, installationResidueValidator: { _ in
            XCTFail("No candidate evidence was attached")
            return true
        })
        service.oldUpdateFiles = [CleanerFileItem(url: fixture.payload, name: "ordinary.zip", size: 3,
                                                  groupId: "oldUpdates", isDirectory: false)]
        let result = await service.cleanAll()
        XCTAssertTrue(checkedOrdinaryGate)
        XCTAssertEqual(result.failed, 1)
    }

    @MainActor
    func testSingleFileRetryStartsFreshAfterPreviousCleanupWasStopped() async throws {
        let fixture = try ResidueFixture()
        defer { fixture.remove() }
        let candidate = try await fixture.candidate()
        weak var serviceReference: SmartCleanerService?
        var attempts = 0
        let service = SmartCleanerService(cleanupFile: { _, permanent in
            XCTAssertFalse(permanent)
            attempts += 1
            if attempts == 1 {
                await MainActor.run { serviceReference?.stopCleaning() }
                return false
            }
            return true
        }, installationResidueScan: { [candidate] }, installationResidueValidator: { value in
            await fixture.scanner.validateForRemoval(value)
        })
        serviceReference = service
        service.oldUpdateFiles = await service.scanInstallationResidues()
        service.toggleCategorySelection(.oldUpdates, forceTo: true)
        let first = await service.cleanAll()
        XCTAssertEqual(first.failed, 1)
        XCTAssertTrue(service.cleaningWasStopped)
        let retained = try XCTUnwrap(service.oldUpdateFiles.first)

        let retried = await service.deleteSingleFile(retained, from: .oldUpdates)

        XCTAssertTrue(retried)
        XCTAssertFalse(service.cleaningWasStopped)
        XCTAssertEqual(attempts, 2)
        XCTAssertTrue(service.oldUpdateFiles.isEmpty)
    }

    @MainActor
    func testCandidateEvidenceCannotAuthorizeADifferentURL() async throws {
        let fixture = try ResidueFixture()
        defer { fixture.remove() }
        let candidate = try await fixture.candidate()
        let service = SmartCleanerService(cleanupFile: { _, _ in
            XCTFail("Mismatched candidate evidence must not reach cleanup")
            return true
        }, installationResidueValidator: { _ in
            XCTFail("Reject a mismatched URL before validating candidate evidence")
            return true
        })
        service.oldUpdateFiles = [CleanerFileItem(url: fixture.payload, name: "wrong target", size: 3,
                                                  groupId: "oldUpdates", isDirectory: false,
                                                  installationResidue: candidate)]
        service.toggleCategorySelection(.oldUpdates, forceTo: true)
        let result = await service.cleanAll()
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(service.oldUpdateFiles.count, 1)
    }

    @MainActor
    func testGenericManagedParentCannotSwallowUnselectedResidue() async throws {
        let fixture = try ResidueFixture()
        defer { fixture.remove() }
        let evidence = try await fixture.candidate()
        let managed = InstallationResidueScanner.Roots.live.codexRuntimes
        // No live directory is created or cleaned: this fixture only exercises
        // model reconciliation against the actual managed-path policy.
        let candidate = InstallationResidue(url: managed.appendingPathComponent("codex-runtime-install-fixture"),
                                            name: "fixture", size: evidence.size,
                                            kind: .codexInstallStaging, identity: evidence.identity)
        let service = SmartCleanerService(installationResidueScan: { [candidate] })
        service.systemCacheFiles = [CleanerFileItem(url: managed, name: "whole runtime root", size: 1_000,
                                                    groupId: "systemCache", isDirectory: true)]
        service.oldUpdateFiles = await service.scanInstallationResidues()
        XCTAssertEqual(service.calculateSize(at: managed), 0)
        await service.deduplicateJunkResults()
        XCTAssertTrue(service.systemCacheFiles.isEmpty)
        XCTAssertEqual(service.oldUpdateFiles.count, 1)
        XCTAssertFalse(service.oldUpdateFiles[0].isSelected)
        XCTAssertEqual(service.systemJunkTotalSize, 0)
    }

    @MainActor
    func testProductionValidatorRejectsEvidenceFromUnmanagedFixtureRoot() async throws {
        let fixture = try ResidueFixture()
        defer { fixture.remove() }
        let candidate = try await fixture.candidate()
        let service = SmartCleanerService(cleanupFile: { _, _ in
            XCTFail("A candidate from another root cannot self-authorize cleanup")
            return true
        }, installationResidueScan: { [candidate] })
        service.oldUpdateFiles = await service.scanInstallationResidues()
        service.toggleCategorySelection(.oldUpdates, forceTo: true)
        let result = await service.cleanAll()
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(service.oldUpdateFiles.count, 1)
    }
}

private struct ResidueFixture {
    let root: URL
    let payload: URL
    let scanner: InstallationResidueScanner

    init(activity: ResidueActivityProbe = ResidueActivityProbe()) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SmartInstallationResidueTests-" + UUID().uuidString)
        let roots = InstallationResidueScanner.Roots(
            applications: root.appendingPathComponent("Applications"), codexRuntimes: root.appendingPathComponent("runtimes"),
            traexCache: root.appendingPathComponent("traex-cache"), temporary: root.appendingPathComponent("temporary"),
            projectBackups: root.appendingPathComponent("backups")
        )
        for directory in [roots.applications, roots.codexRuntimes, roots.traexCache, roots.temporary, roots.projectBackups] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let backup = roots.applications.appendingPathComponent(".MacOptimizer-Update-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let payload = backup.appendingPathComponent("payload.bin")
        try Data([1, 2, 3]).write(to: payload)
        let future = Date().addingTimeInterval(8 * 24 * 60 * 60)
        self.root = root
        self.payload = payload
        self.scanner = InstallationResidueScanner(roots: roots, now: { future }, activity: { activity.snapshot() })
    }

    func candidate() async throws -> InstallationResidue {
        let candidates = await scanner.scan()
        XCTAssertEqual(candidates.count, 1)
        return try XCTUnwrap(candidates.first)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class ResidueActivityProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []

    func setActivePaths(_ paths: [String]) {
        lock.lock(); defer { lock.unlock() }
        self.paths = paths
    }

    func snapshot() -> InstallationResidueScanner.ActivitySnapshot {
        lock.lock(); defer { lock.unlock() }
        return .init(activePaths: paths, isComplete: true)
    }
}
