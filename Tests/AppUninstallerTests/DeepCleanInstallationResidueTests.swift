import XCTest
import Combine
@testable import AppUninstaller

private final class DeepCleanResidueActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: [String] = []
    func set(_ paths: [String]) { lock.lock(); self.paths = paths; lock.unlock() }
    func read() -> InstallationResidueScanner.ActivitySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return .init(activePaths: paths, isComplete: true)
    }
}

private actor DeepCleanResidueGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

final class DeepCleanInstallationResidueTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("DeepCleanInstallation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func fixture(activity: DeepCleanResidueActivity = DeepCleanResidueActivity()) async throws
        -> (scanner: InstallationResidueScanner, candidate: InstallationResidue, payload: URL) {
        let roots = InstallationResidueScanner.Roots(
            applications: root.appendingPathComponent("applications"),
            codexRuntimes: root.appendingPathComponent("runtimes"),
            traexCache: root.appendingPathComponent("cache"),
            temporary: root.appendingPathComponent("temporary"),
            projectBackups: root.appendingPathComponent("backups"))
        for directory in [roots.applications, roots.codexRuntimes, roots.traexCache, roots.temporary, roots.projectBackups] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let candidate = roots.temporary.appendingPathComponent("macoptimizer-cleanup-fix-fixture")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        let payload = candidate.appendingPathComponent("payload.bin")
        try Data([1, 2, 3, 4]).write(to: payload)
        let future = Date().addingTimeInterval(8 * 24 * 60 * 60)
        let scanner = InstallationResidueScanner(roots: roots, now: { future }, activity: { activity.read() })
        let candidates = await scanner.scan()
        return (scanner, try XCTUnwrap(candidates.first), payload)
    }

    @MainActor
    func testInstallationCategoryStartsUnselectedAndUsesFreshScopedValidation() async throws {
        let fixture = try await fixture()
        var removed: [URL] = []
        var checks = 0
        var genericChecks = 0
        var progress: [Double] = []
        let scanner = DeepCleanScanner(scanCategory: { _ in [] }, trashItem: { removed.append($0) },
            deletionAllowed: { _, _ in genericChecks += 1; return false }, recordFailure: { _ in },
            scanInstallationResidues: { [fixture.candidate] }, residueValidator: {
                checks += 1
                return await fixture.scanner.validateForRemoval($0)
            })
        let subscription = scanner.$scanProgress.sink { progress.append($0) }
        defer { subscription.cancel() }
        await scanner.startScan()
        XCTAssertEqual(scanner.items.count, 1)
        XCTAssertEqual(scanner.items.first?.category, .installationResidues)
        XCTAssertEqual(scanner.items.first?.installationResidue, fixture.candidate)
        XCTAssertNotNil(scanner.items.first?.installationReviewReason)
        XCTAssertFalse(try XCTUnwrap(scanner.items.first).isSelected)
        XCTAssertEqual(scanner.selectedCount, 0)
        XCTAssertEqual(scanner.totalSize, 4)
        XCTAssertEqual(scanner.completedCategories, Set(DeepCleanCategory.allCases))
        XCTAssertEqual(scanner.scanProgress, 1)
        XCTAssertTrue(zip(progress, progress.dropFirst()).allSatisfy { $0 <= $1 })
        let untouched = await scanner.cleanSelected()
        XCTAssertEqual(untouched.count, 0)
        XCTAssertEqual(checks, 0)
        XCTAssertTrue(removed.isEmpty)

        scanner.items[0].isSelected = true
        let result = await scanner.cleanSelected()
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(genericChecks, 0, "The complete scoped safety gate replaces the generic Applications prohibition")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.size, 4)
        XCTAssertEqual(removed, [fixture.candidate.url])
    }

    @MainActor
    func testChangedInstallationTreeIsRetainedBeforeTrash() async throws {
        let fixture = try await fixture()
        var removed = 0
        let scanner = DeepCleanScanner(scanCategory: { _ in [] }, trashItem: { _ in removed += 1 },
            deletionAllowed: { _, _ in true }, recordFailure: { _ in },
            scanInstallationResidues: { [fixture.candidate] },
            residueValidator: { await fixture.scanner.validateForRemoval($0) })
        await scanner.startScan()
        scanner.items[0].isSelected = true
        try Data([9, 8, 7, 6, 5]).write(to: fixture.payload)
        let result = await scanner.cleanSelected()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(scanner.items.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.payload.path))
    }

    @MainActor
    func testNewlyActiveInstallationCannotBeRemovedIndividually() async throws {
        let activity = DeepCleanResidueActivity()
        let fixture = try await fixture(activity: activity)
        var removed = 0
        let scanner = DeepCleanScanner(trashItem: { _ in removed += 1 }, deletionAllowed: { _, _ in true },
            recordFailure: { _ in }, residueValidator: { await fixture.scanner.validateForRemoval($0) })
        let item = DeepCleanItem(url: fixture.candidate.url, name: "installation", size: 4,
                                category: .installationResidues, installationResidue: fixture.candidate)
        scanner.items = [item]
        activity.set([fixture.payload.path])
        let removedItem = await scanner.deleteSingleItem(item)
        XCTAssertFalse(removedItem)
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(scanner.lastFailures.count, 1)
        XCTAssertEqual(scanner.items.count, 1)
    }

    @MainActor
    func testMissingCandidateIdentityCannotUseGenericAllowance() async {
        var removed = 0
        var validations = 0
        let scanner = DeepCleanScanner(trashItem: { _ in removed += 1 }, deletionAllowed: { _, _ in true },
            recordFailure: { _ in }, residueValidator: { _ in validations += 1; return true })
        scanner.items = [DeepCleanItem(url: root.appendingPathComponent("unknown"), name: "unknown", size: 4,
                                      category: .installationResidues, isSelected: true)]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(validations, 0)
        XCTAssertEqual(result.failures.count, 1)
    }

    @MainActor
    func testGenericManagedParentIsExcludedAndCannotUseLargeFileOverride() async throws {
        let managed = try XCTUnwrap(InstallationResidueScanner.managedRootPaths.first)
        let parent = URL(fileURLWithPath: managed).deletingLastPathComponent()
        let item = DeepCleanItem(url: parent, name: "parent", size: 1_000, category: .systemCaches)
        let scanner = DeepCleanScanner(scanCategory: { $0 == .systemCaches ? [item] : [] })
        await scanner.startScan()
        XCTAssertTrue(scanner.items.isEmpty)
        XCTAssertEqual(scanner.totalSize, 0)

        var removed = 0
        let direct = DeepCleanScanner(trashItem: { _ in removed += 1 }, deletionAllowed: { _, _ in true }, recordFailure: { _ in })
        direct.items = [DeepCleanItem(url: URL(fileURLWithPath: managed), name: "runtime", size: 1_000,
                                     category: .largeFiles, isSelected: true)]
        let result = await direct.cleanSelected()
        XCTAssertEqual(removed, 0)
        XCTAssertEqual(result.failures.count, 1)
    }

    @MainActor
    func testCancelledInstallationScanCannotPublishLateCandidates() async throws {
        let fixture = try await fixture()
        let entered = expectation(description: "Installation scan started")
        let gate = DeepCleanResidueGate()
        let scanner = DeepCleanScanner(scanCategory: { _ in [] }, scanInstallationResidues: {
            entered.fulfill()
            await gate.wait()
            return [fixture.candidate]
        })
        let task = Task { await scanner.startScan() }
        await fulfillment(of: [entered], timeout: 3)
        scanner.stopScan()
        XCTAssertTrue(scanner.isScanning)
        await gate.open()
        await task.value
        XCTAssertTrue(scanner.scanWasStopped)
        XCTAssertTrue(scanner.items.isEmpty)
        XCTAssertFalse(scanner.completedCategories.contains(.installationResidues))
        XCTAssertLessThan(scanner.scanProgress, 1)
    }

    @MainActor
    func testCancellationDuringValidationPreventsTrash() async throws {
        let fixture = try await fixture()
        let entered = expectation(description: "Validation started")
        let gate = DeepCleanResidueGate()
        var removed = 0
        let scanner = DeepCleanScanner(trashItem: { _ in removed += 1 }, recordFailure: { _ in }, residueValidator: { _ in
            entered.fulfill()
            await gate.wait()
            return true
        })
        scanner.items = [DeepCleanItem(url: fixture.candidate.url, name: "installation", size: 4,
                                      category: .installationResidues, isSelected: true,
                                      installationResidue: fixture.candidate)]
        let task = Task { await scanner.cleanSelected() }
        await fulfillment(of: [entered], timeout: 3)
        task.cancel()
        await gate.open()
        let result = await task.value
        XCTAssertEqual(removed, 0)
        XCTAssertTrue(result.wasStopped)
        XCTAssertEqual(scanner.items.count, 1)
    }
}
