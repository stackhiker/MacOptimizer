import XCTest
import Darwin
@testable import AppUninstaller

private final class InstallationActivityFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot = InstallationResidueScanner.ActivitySnapshot(activePaths: [], isComplete: true)
    func set(_ value: InstallationResidueScanner.ActivitySnapshot) { lock.lock(); snapshot = value; lock.unlock() }
    func read() -> InstallationResidueScanner.ActivitySnapshot { lock.lock(); defer { lock.unlock() }; return snapshot }
}

final class InstallationResidueScannerTests: XCTestCase {
    private var directory: URL!
    private var roots: InstallationResidueScanner.Roots!
    private var clock: Date!
    private var activity: InstallationActivityFixture!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("InstallationResidueTests-\(UUID())")
        roots = .init(applications: directory.appendingPathComponent("Applications"),
                      codexRuntimes: directory.appendingPathComponent("codex-runtimes"),
                      traexCache: directory.appendingPathComponent("TraexCache"),
                      temporary: directory.appendingPathComponent("temporary"),
                      projectBackups: directory.appendingPathComponent("backups"))
        for root in [roots.applications, roots.codexRuntimes, roots.traexCache, roots.temporary, roots.projectBackups] {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        clock = Date().addingTimeInterval(8 * 86400)
        activity = InstallationActivityFixture()
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func expectTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(value, message, file: file, line: line) }
    private func expectFalse(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertFalse(value, message, file: file, line: line) }
    private func scanner(budget: InstallationResidueScanner.Budget = .init(), owner: UInt32 = getuid()) -> InstallationResidueScanner {
        let date = clock!, activity = activity!
        return .init(roots: roots, now: { date }, activity: { activity.read() }, budget: budget, ownerUID: owner)
    }
    @discardableResult private func file(_ url: URL, text: String = "payload") throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }
    private func backup() throws -> URL {
        let url = roots.applications.appendingPathComponent(".MacOptimizer-Update-\(UUID())")
        try file(url.appendingPathComponent("payload.bin"))
        return url
    }
    private func onlyCandidate(_ scanner: InstallationResidueScanner) async throws -> InstallationResidue {
        let found = await scanner.scan()
        XCTAssertEqual(found.count, 1)
        return try XCTUnwrap(found.first)
    }

    func testExactRulesCoverFiveKindsAndKeepPrimaryRuntimeAndNewestBackup() async throws {
        let app = try backup()
        let staging = roots.codexRuntimes.appendingPathComponent("codex-runtime-install-fixture")
        try file(staging.appendingPathComponent("bin/tool"))
        try file(roots.codexRuntimes.appendingPathComponent("codex-primary-runtime/bin/tool"))
        try file(roots.temporary.appendingPathComponent("macoptimizer-cleanup-fix-fixture/payload"))
        try file(roots.temporary.appendingPathComponent("macoptimizer-personal-documents/user-data"))
        try file(roots.traexCache.appendingPathComponent("org.sparkle-project.Sparkle/PersistentDownloads/id/Traex App 1/update.zip"))
        try file(roots.traexCache.appendingPathComponent("unrelated.zip"))
        let old = try file(roots.projectBackups.appendingPathComponent("MacOptimizer_v5.0_build7_before_build8_20261101T000000Z.zip"))
        let newest = try file(roots.projectBackups.appendingPathComponent("MacOptimizer_v5.0_build8_before_build9_20261102T000000Z.zip"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100)], ofItemAtPath: old.path)
        let found = await scanner().scan()
        XCTAssertEqual(found.count, 5)
        XCTAssertEqual(Set(found.map(\.kind)), Set([.appBackup, .codexInstallStaging, .sparkleDownload, .verificationTemporary, .projectBackup]))
        XCTAssertTrue(found.contains { $0.url.standardizedFileURL.path == app.standardizedFileURL.path })
        XCTAssertFalse(found.contains { $0.url == newest || $0.url.path.contains("codex-primary-runtime") })
    }

    func testCurrentRuntimeAliasProtectsStagingWithoutRunningProcess() async throws {
        let staging = roots.codexRuntimes.appendingPathComponent("codex-runtime-install-fixture")
        try file(staging.appendingPathComponent("bin/tool"))
        let service = scanner()
        let candidate = try await onlyCandidate(service)
        try FileManager.default.createSymbolicLink(at: roots.codexRuntimes.appendingPathComponent("codex-primary-runtime"), withDestinationURL: staging)
        expectTrue(await service.scan().isEmpty)
        expectFalse(await service.validateForRemoval(candidate))
    }

    func testNewRootAndNewDescendantArePreserved() async throws {
        let app = try backup()
        let live = InstallationResidueScanner(roots: roots, activity: { .init(activePaths: [], isComplete: true) })
        expectTrue(await live.scan().isEmpty)
        try FileManager.default.setAttributes([.modificationDate: clock!], ofItemAtPath: app.appendingPathComponent("payload.bin").path)
        expectTrue(await scanner().scan().isEmpty)
    }

    func testRootExternalAndManagedRootSymlinksAreRejected() async throws {
        let outside = directory.appendingPathComponent("outside")
        try file(outside.appendingPathComponent("keep"))
        let alias = roots.applications.appendingPathComponent(".Traex.app.backup.123")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: outside)
        let app = try backup()
        try FileManager.default.createSymbolicLink(at: app.appendingPathComponent("external"), withDestinationURL: outside)
        expectTrue(await scanner().scan().isEmpty)
        try FileManager.default.removeItem(at: roots.codexRuntimes)
        try FileManager.default.createSymbolicLink(at: roots.codexRuntimes, withDestinationURL: outside)
        try file(outside.appendingPathComponent("codex-runtime-install-fixture/payload"))
        expectTrue(await scanner().scan().isEmpty)
    }

    func testInternalFrameworkLinksAreAcceptedWithoutDoubleCounting() async throws {
        let app = roots.applications.appendingPathComponent(".Traex.app.runtime.backup.123")
        let framework = app.appendingPathComponent("Traex.app/Contents/Frameworks/Test.framework")
        try file(framework.appendingPathComponent("Versions/A/Test"), text: "1234567")
        try FileManager.default.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        try FileManager.default.createSymbolicLink(atPath: framework.appendingPathComponent("Test").path, withDestinationPath: "Versions/Current/Test")
        let candidate = try await onlyCandidate(scanner())
        XCTAssertEqual(candidate.size, 7)
        expectTrue(await scanner().validateForRemoval(candidate))
        try FileManager.default.removeItem(at: framework.appendingPathComponent("Test"))
        try FileManager.default.createSymbolicLink(atPath: framework.appendingPathComponent("Test").path, withDestinationPath: "/etc/hosts")
        expectFalse(await scanner().validateForRemoval(candidate))
    }

    func testFreshActivityAndIncompleteObservationPreventRemoval() async throws {
        let app = try backup()
        let service = scanner()
        let candidate = try await onlyCandidate(service)
        activity.set(.init(activePaths: [app.appendingPathComponent("payload.bin").path], isComplete: true))
        expectFalse(await service.validateForRemoval(candidate))
        expectTrue(await service.scan().isEmpty)
        activity.set(.init(activePaths: [], isComplete: false))
        expectFalse(await service.validateForRemoval(candidate))
        expectTrue(await service.scan().isEmpty)
    }

    func testReplacementAndDescendantMutationInvalidateIdentity() async throws {
        let app = try backup()
        let service = scanner()
        let original = try await onlyCandidate(service)
        try file(app.appendingPathComponent("payload.bin"), text: "changed")
        expectFalse(await service.validateForRemoval(original))
        let updated = try await onlyCandidate(service)
        let moved = roots.applications.appendingPathComponent("preserved-original")
        try FileManager.default.moveItem(at: app, to: moved)
        try file(app.appendingPathComponent("payload.bin"), text: "changed")
        expectFalse(await service.validateForRemoval(updated))
    }

    func testForgedKindOutOfScopeOwnerAndCancellationAreRejected() async throws {
        _ = try backup()
        let service = scanner()
        let original = try await onlyCandidate(service)
        let forged = InstallationResidue(url: original.url, name: original.name, size: original.size,
                                         kind: .sparkleDownload, identity: original.identity)
        expectFalse(await service.validateForRemoval(forged))
        let unrelated = InstallationResidue(url: directory, name: "outside", size: original.size,
                                           kind: .appBackup, identity: original.identity)
        expectFalse(await service.validateForRemoval(unrelated))
        expectTrue(await scanner(owner: getuid() &+ 1).scan().isEmpty)
        expectTrue(await service.scan(shouldCancel: { true }).isEmpty)
        expectFalse(await service.validateForRemoval(original, shouldCancel: { true }))
    }

    func testEntryAndCandidateBudgetsDoNotPublishPartialTrees() async throws {
        let app = try backup()
        for n in 0..<20 { try file(app.appendingPathComponent("file-\(n)")) }
        expectTrue(await scanner(budget: .init(maximumCandidates: 512, maximumEntries: 5, timeout: 20)).scan().isEmpty)
        expectTrue(await scanner(budget: .init(maximumCandidates: 0, maximumEntries: 1000, timeout: 20)).scan().isEmpty)
    }

    func testLatestBackupIsReevaluatedBeforeRemoval() async throws {
        let old = try file(roots.projectBackups.appendingPathComponent("MacOptimizer_v5.0_build7_before_build8_20261101T000000Z.zip"))
        let newest = try file(roots.projectBackups.appendingPathComponent("MacOptimizer_v5.0_build8_before_build9_20261102T000000Z.zip"))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100)], ofItemAtPath: old.path)
        let service = scanner()
        let candidate = try await onlyCandidate(service)
        try FileManager.default.removeItem(at: newest)
        expectFalse(await service.validateForRemoval(candidate), "The last usable rollback backup must remain")
    }

    func testManagedRootAncestorsCannotBeSwallowedByGenericCleanup() {
        XCTAssertTrue(InstallationResidueScanner.excludesGenericCleanup(path: roots.codexRuntimes.deletingLastPathComponent().path, roots: roots))
        XCTAssertTrue(InstallationResidueScanner.excludesGenericCleanup(path: roots.codexRuntimes.appendingPathComponent("codex-primary-runtime").path, roots: roots))
        XCTAssertTrue(InstallationResidueScanner.excludesGenericCleanup(path: roots.traexCache.path, roots: roots))
        XCTAssertTrue(InstallationResidueScanner.excludesGenericCleanup(path: roots.temporary.appendingPathComponent("macoptimizer-cleanup-fix-fixture/child").path, roots: roots))
        XCTAssertFalse(InstallationResidueScanner.excludesGenericCleanup(path: roots.temporary.appendingPathComponent("ordinary-old.tmp").path, roots: roots))
        XCTAssertFalse(InstallationResidueScanner.excludesGenericCleanup(path: roots.codexRuntimes.path + "-other/file", roots: roots))
    }
}
