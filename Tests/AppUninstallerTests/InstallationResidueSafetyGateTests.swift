import XCTest
@testable import AppUninstaller

final class InstallationResidueSafetyGateTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory.appendingPathComponent("ResidueSafetyGate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: fixture)
    }

    private func candidate() async throws -> (InstallationResidueScanner, InstallationResidue) {
        let roots = InstallationResidueScanner.Roots(
            applications: fixture.appendingPathComponent("Applications"),
            codexRuntimes: fixture.appendingPathComponent("runtimes"),
            traexCache: fixture.appendingPathComponent("cache"),
            temporary: fixture.appendingPathComponent("temp"),
            projectBackups: fixture.appendingPathComponent("backups"))
        let directory = roots.temporary.appendingPathComponent("macoptimizer-cleanup-fix-fixture")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: directory.appendingPathComponent("payload.bin"))
        let scanner = InstallationResidueScanner(roots: roots,
            now: { Date().addingTimeInterval(8 * 86400) },
            activity: { .init(activePaths: [], isComplete: true) })
        let candidates = await scanner.scan()
        return (scanner, try XCTUnwrap(candidates.first))
    }

    @MainActor
    func testLegacyFreshGuardAllowsOnlySelectedValidatedResidue() async throws {
        let (scanner, residue) = try await candidate()
        var removed: [URL] = []
        let cleaner = JunkCleaner(deleteFile: { removed.append($0) },
            deletionAllowed: { _, _ in false }, recordFailure: { _ in },
            validateInstallationResidue: { await scanner.validateForRemoval($0) })
        let item = JunkItem(type: .oldUpdates, path: residue.url, size: residue.size,
                            installationResidue: residue)
        XCTAssertFalse(item.isSelected)
        item.isSelected = true
        cleaner.junkItems = [item]
        let result = await cleaner.cleanSelected()
        XCTAssertEqual(result.cleaned, residue.size)
        XCTAssertEqual(removed, [residue.url])
        XCTAssertTrue(cleaner.junkItems.isEmpty)
    }

    @MainActor
    func testLegacyFreshGuardRetainsChangedResidue() async throws {
        let (scanner, residue) = try await candidate()
        var removed: [URL] = []
        let cleaner = JunkCleaner(deleteFile: { removed.append($0) },
            deletionAllowed: { _, _ in true }, recordFailure: { _ in },
            validateInstallationResidue: { await scanner.validateForRemoval($0) })
        let item = JunkItem(type: .oldUpdates, path: residue.url, size: residue.size,
                            installationResidue: residue)
        item.isSelected = true
        cleaner.junkItems = [item]
        try Data([4, 5, 6, 7]).write(to: residue.url.appendingPathComponent("payload.bin"))
        let result = await cleaner.cleanSelected()
        XCTAssertEqual(result.cleaned, 0)
        XCTAssertEqual(result.failed, residue.size)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(cleaner.junkItems.count, 1)
    }

    @MainActor
    func testStoppingDuringLegacyValidationKeepsTheCandidate() async throws {
        let (_, residue) = try await candidate()
        var removed = false
        var cleaner: JunkCleaner!
        cleaner = JunkCleaner(deleteFile: { _ in removed = true }, recordFailure: { _ in },
            validateInstallationResidue: { _ in
                cleaner.stopCleaningRequested = true
                return true
            })
        let item = JunkItem(type: .oldUpdates, path: residue.url, size: residue.size,
                            installationResidue: residue)
        item.isSelected = true
        cleaner.junkItems = [item]
        let result = await cleaner.cleanSelected()
        XCTAssertEqual(result.cleaned, 0)
        XCTAssertFalse(removed)
        XCTAssertEqual(cleaner.junkItems.count, 1)
    }

    @MainActor
    func testNewMailCleanupIgnoresPreviousSystemCleanupStop() async {
        var removed: [URL] = []
        let cleaner = JunkCleaner(deleteFile: { removed.append($0) },
            deletionAllowed: { _, _ in true }, recordFailure: { _ in })
        cleaner.stopCleaningRequested = true
        let url = fixture.appendingPathComponent("attachment.pdf")
        let item = JunkItem(type: .mailAttachments, path: url, size: 10)
        item.isSelected = true
        cleaner.junkItems = [item]
        let result = await cleaner.cleanSelectedMailAttachments()
        XCTAssertEqual(result.cleaned, 10)
        XCTAssertEqual(removed, [url])
    }

    func testNarrowSafetyGateRejectsCandidateOutsideLiveRoots() async throws {
        let (_, residue) = try await candidate()
        let allowed = await SafetyGuard.shared.isSafeToDeleteInstallationResidue(residue)
        XCTAssertFalse(allowed)
    }

    func testRuntimeAndRollbackRootsCannotUseGenericDeletionOverride() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for relative in [
            ".cache/codex-runtimes",
            ".cache/codex-runtimes/current/bin/node",
            "Library/Caches/com.bytedance.local.traex.runtime",
            "workspace/MacOptimizer/build/backups"
        ] {
            let url = home.appendingPathComponent(relative)
            XCTAssertFalse(SafetyGuard.shared.isSafeToDelete(url), relative)
            XCTAssertFalse(SafetyGuard.shared.isSafeToDelete(url, ignoreProtection: true), relative)
        }
    }

    @MainActor
    func testLegacyGenericCleanupCannotDeleteManagedRuntimeEvenWithInjectedAllowance() async {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/codex-runtimes/current")
        var removed: [URL] = []
        let cleaner = JunkCleaner(deleteFile: { removed.append($0) },
                                  deletionAllowed: { _, _ in true }, recordFailure: { _ in })
        let item = JunkItem(type: .userCache, path: url, size: 100)
        item.isSelected = true
        cleaner.junkItems = [item]
        let result = await cleaner.cleanSelected()
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(result.cleaned, 0)
        XCTAssertEqual(result.failed, 100)
        XCTAssertEqual(cleaner.junkItems.count, 1)
    }

    func testOrdinaryCacheDoesNotBecomeManagedRuntimeBySubstring() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertFalse(InstallationResidueScanner.excludesGenericCleanup(
            home.appendingPathComponent("Library/Caches/runtime-test")))
        XCTAssertFalse(InstallationResidueScanner.excludesGenericCleanup(
            home.appendingPathComponent(".cache/codex-runtimes-other/cache")))
    }

    func testLegacyResidueCategoryRequiresManualSelection() {
        XCTAssertFalse(JunkType.oldUpdates.automaticallySelected)
        let item = JunkItem(type: .oldUpdates, path: URL(fileURLWithPath: "/fixture/old.zip"), size: 10)
        XCTAssertFalse(item.isSelected)
        XCTAssertFalse(JunkCleaner.shouldSelectByDefault(item))
    }
}
