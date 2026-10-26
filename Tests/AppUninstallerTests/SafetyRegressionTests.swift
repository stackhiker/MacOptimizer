import XCTest
import AppKit
import CryptoKit
@testable import AppUninstaller

private actor RegressionGate {
    private var opened = false
    private var continuations: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func open() {
        opened = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor RegressionTrace {
    private var log: [String] = []
    func append(_ value: String) { log.append(value) }
    func values() -> [String] { log }
}

private final class RegressionSecrets: AISecretStore {
    var values: [String: String] = [:]
    var failWrites = false
    func read(account: String) throws -> String? { values[account] }
    func write(_ value: String, account: String) throws {
        if failWrites { throw POSIXError(.EACCES) }
        values[account] = value.isEmpty ? nil : value
    }
}

final class SafetyRegressionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacOptimizerRegression-\(UUID().uuidString)", isDirectory: true)
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

    func testQueueSerializesConcurrentCallersAcrossAwait() async throws {
        let queue = BackgroundTaskQueue()
        let gate = RegressionGate()
        let trace = RegressionTrace()
        let first = Task {
            try await queue.enqueue {
                await trace.append("first-start")
                await gate.wait()
                await trace.append("first-end")
            }
        }
        let started = await waitUntil { await queue.isCurrentlyProcessing }
        XCTAssertTrue(started)
        let second = Task { try await queue.enqueue { await trace.append("second") } }
        let pending = await waitUntil { await queue.pendingCount == 1 }
        XCTAssertTrue(pending)
        let before = await trace.values()
        XCTAssertEqual(before, ["first-start"])
        await gate.open()
        try await first.value
        try await second.value
        let after = await trace.values()
        XCTAssertEqual(after, ["first-start", "first-end", "second"])
        let processing = await queue.isCurrentlyProcessing
        XCTAssertFalse(processing)
    }

    func testCancelAllSkipsWaitingOperationsAndKeepsRunningOwnership() async throws {
        let queue = BackgroundTaskQueue()
        let gate = RegressionGate()
        let first = Task { try await queue.enqueue { await gate.wait() } }
        let started = await waitUntil { await queue.isCurrentlyProcessing }
        XCTAssertTrue(started)
        let waiting = Task { try await queue.enqueue { XCTFail("Cancelled work started") } }
        let pending = await waitUntil { await queue.pendingCount == 1 }
        XCTAssertTrue(pending)
        await queue.cancelAll()
        do { try await waiting.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { throw error }
        let processing = await queue.isCurrentlyProcessing
        XCTAssertTrue(processing)
        await gate.open()
        try await first.value
        let result = try await queue.enqueue { 42 }
        XCTAssertEqual(result, 42)
    }

    func testIndividualWaitingCallerCanCancel() async throws {
        let queue = BackgroundTaskQueue()
        let gate = RegressionGate()
        let first = Task { try await queue.enqueue { await gate.wait() } }
        let started = await waitUntil { await queue.isCurrentlyProcessing }
        XCTAssertTrue(started)
        let waiting = Task { try await queue.enqueue { XCTFail("Cancelled work started") } }
        let pending = await waitUntil { await queue.pendingCount == 1 }
        XCTAssertTrue(pending)
        waiting.cancel()
        do { try await waiting.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { throw error }
        await gate.open()
        try await first.value
    }

    func testShredderRejectsLinksBeforeOverwritingAnyDirectoryContent() throws {
        let selected = root.appendingPathComponent("selected")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.txt")
        let inside = selected.appendingPathComponent("inside.txt")
        let data = Data("must remain intact".utf8)
        try data.write(to: outside)
        try data.write(to: inside)
        try FileManager.default.createSymbolicLink(at: selected.appendingPathComponent("link.txt"), withDestinationURL: outside)
        XCTAssertThrowsError(try SecureFileShredder.shred(at: selected))
        XCTAssertEqual(try Data(contentsOf: outside), data)
        XCTAssertEqual(try Data(contentsOf: inside), data)
    }

    func testShredderRejectsSelectedSymlinkAndHardLink() throws {
        let outside = root.appendingPathComponent("outside.txt")
        let data = Data("must remain intact".utf8)
        try data.write(to: outside)
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try SecureFileShredder.shred(at: link))
        let hardLink = root.appendingPathComponent("hard.txt")
        try FileManager.default.linkItem(at: outside, to: hardLink)
        XCTAssertThrowsError(try SecureFileShredder.shred(at: hardLink))
        XCTAssertEqual(try Data(contentsOf: outside), data)
    }

    func testShredderRemovesOrdinaryNestedFiles() throws {
        let selected = root.appendingPathComponent("selected")
        let nested = selected.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 42, count: 1024 * 1024 + 17).write(to: nested.appendingPathComponent("file.bin"))
        try SecureFileShredder.shred(at: selected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: selected.path))
    }

    @MainActor
    func testFailedLargeFileDeletionPreservesItemSizeAndSelection() async throws {
        let good = root.appendingPathComponent("good.txt")
        let bad = root.appendingPathComponent("bad.txt")
        try Data("test".utf8).write(to: good)
        try Data("keep".utf8).write(to: bad)
        let scanner = LargeFileScanner(deleteFile: { url in
            if url == bad { throw POSIXError(.EACCES) }
            try FileManager.default.removeItem(at: url)
        })
        let first = FileItem(url: good, name: "good", size: 4, type: "TXT", accessDate: Date())
        let second = FileItem(url: bad, name: "bad", size: 4, type: "TXT", accessDate: Date())
        scanner.foundFiles = [first, second]
        scanner.selectedFiles = [first.id, second.id]
        scanner.totalSize = 8
        let result = await scanner.deleteItems(scanner.selectedFiles)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(scanner.foundFiles.map(\.id), [second.id])
        XCTAssertEqual(scanner.totalSize, 4)
        XCTAssertEqual(scanner.selectedFiles, [second.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: bad.path))
    }

    @MainActor
    func testNewUnindexedLargeFileIsFound() async throws {
        let file = root.appendingPathComponent("new.bin")
        try Data().write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 51 * 1024 * 1024)
        try handle.close()
        let scanner = LargeFileScanner()
        await scanner.scan(at: root)
        XCTAssertEqual(scanner.foundFiles.map { $0.url.standardizedFileURL }, [file.standardizedFileURL])
        XCTAssertTrue(scanner.hasCompletedScan)
    }

    @MainActor
    func testTrashFailureNeverFallsBackToPermanentDeletion() async {
        var permanentlyDeleted = false
        let remover = FileRemover(trashItem: { _ in throw POSIXError(.EACCES) },
                                  removeItem: { _ in permanentlyDeleted = true }, recordFailure: { _ in })
        let app = InstalledApp(name: "Fixture", path: root.appendingPathComponent("Fixture.app"), bundleIdentifier: "test.fixture", icon: NSImage(), size: 10)
        let result = await remover.removeApp(app, moveToTrash: true)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertFalse(permanentlyDeleted)
    }

    @MainActor
    func testSmartCleanupDeduplicatesAndKeepsUnselectedAndFailedFiles() async {
        let good = CleanerFileItem(url: root.appendingPathComponent("good"), name: "good", size: 10, groupId: "cache")
        let bad = CleanerFileItem(url: root.appendingPathComponent("bad"), name: "bad", size: 20, groupId: "cache")
        let unselected = CleanerFileItem(url: root.appendingPathComponent("keep"), name: "keep", size: 30, groupId: "cache", isSelected: false)
        let trace = RegressionTrace()
        let service = SmartCleanerService(cleanupFile: { url, _ in
            await trace.append(url.lastPathComponent)
            return url != bad.url
        }, deletionAllowed: { _, _ in true })
        service.userCacheFiles = [good, bad, unselected]
        service.systemCacheFiles = [good]
        let result = await service.cleanAll()
        let operations = await trace.values()
        XCTAssertEqual(operations, ["good", "bad"])
        XCTAssertEqual(result.success, 1)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.size, 10)
        XCTAssertEqual(Set(service.userCacheFiles.map(\.url)), [bad.url, unselected.url])
        XCTAssertTrue(service.systemCacheFiles.isEmpty)
    }

    @MainActor
    func testStoppingCleanupKeepsOwnershipUntilCurrentFileFinishes() async {
        let gate = RegressionGate()
        let trace = RegressionTrace()
        let service = SmartCleanerService(cleanupFile: { url, _ in
            await trace.append(url.lastPathComponent)
            await gate.wait()
            return true
        }, deletionAllowed: { _, _ in true })
        service.userCacheFiles = ["one", "two"].map {
            CleanerFileItem(url: root.appendingPathComponent($0), name: $0, size: 10, groupId: "cache")
        }
        let run = Task { await service.cleanAll() }
        let entered = await waitUntil { await trace.values().count == 1 }
        XCTAssertTrue(entered)
        service.stopCleaning()
        XCTAssertTrue(service.isCleaning)
        let overlapping = await service.cleanAll()
        XCTAssertEqual(overlapping.success, 0)
        await gate.open()
        let result = await run.value
        XCTAssertEqual(result.success, 1)
        XCTAssertEqual(service.userCacheFiles.map(\.name), ["two"])
        XCTAssertTrue(service.cleaningWasStopped)
        XCTAssertFalse(service.isCleaning)
    }

    @MainActor
    func testProtectedPathCannotEnterRetryDeletion() async {
        let service = SmartCleanerService(cleanupFile: { _, _ in
            XCTFail("Safety refusal was bypassed")
            return true
        }, deletionAllowed: { _, _ in false })
        let item = CleanerFileItem(url: root.appendingPathComponent("blocked-$(printf test)"), name: "blocked", size: 10, groupId: "cache")
        service.userCacheFiles = [item]
        let result = await service.cleanAll()
        XCTAssertEqual(result.failed, 1)
        let retry = await service.retryFailedFiles(result.failedFiles)
        XCTAssertEqual(retry.failed, 1)
        XCTAssertEqual(service.userCacheFiles.map(\.url), [item.url])
    }

    func testChromeResidualsExcludeSharedGoogleDirectory() async throws {
        let chrome = root.appendingPathComponent("Library/Application Support/Google/Chrome")
        let other = root.appendingPathComponent("Library/Application Support/Google/OtherApp")
        try FileManager.default.createDirectory(at: chrome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let app = InstalledApp(name: "Chrome", path: root.appendingPathComponent("Chrome.app"), bundleIdentifier: "com.google.Chrome", icon: NSImage(), size: 10)
        let result = await ResidualFileScanner(homeDirectory: root).scanResidualFiles(for: app)
        XCTAssertEqual(result.map { $0.path.path }, [chrome.path])
    }

    func testStreamingHashAndCancellation() throws {
        let data = Data(repeating: 0xA5, count: 3 * 1024 * 1024 + 37)
        let file = root.appendingPathComponent("hash.bin")
        try data.write(to: file)
        let expected = Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(FileHashing.md5(at: file), expected)
        XCTAssertNil(FileHashing.md5(at: file, shouldCancel: { true }))
    }

    func testHashConcurrencyAcceptsZeroLimitWithoutHanging() async throws {
        let file = root.appendingPathComponent("hash.txt")
        try Data("test".utf8).write(to: file)
        let results = await computeHashesConcurrently(for: [file], maxConcurrency: 0)
        XCTAssertEqual(results[file], FileHashing.md5(at: file))
    }

    @MainActor
    func testParentCancellationPreventsThreatDeletionEvenDuringStartup() async throws {
        let file = root.appendingPathComponent("threat-fixture")
        let contents = Data("retain on cancellation".utf8)
        try contents.write(to: file)
        let scanner = MalwareScanner()
        scanner.threats = [DetectedThreat(name: "fixture", type: .adware, path: file, size: Int64(contents.count))]
        let result = await scanner.removeThreats(shouldCancel: { true })
        XCTAssertEqual(result.success, 0)
        XCTAssertEqual(scanner.threats.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), contents)
    }

    private func legacySettingsFile() throws -> URL {
        let url = root.appendingPathComponent("settings.json")
        let settings: [String: Any] = ["activeProvider": "openAI", "providers": ["openAI": [
            "baseURL": "https://example.invalid/v1", "model": "fixture", "apiKey": "fixture-secret"
        ]]]
        try JSONSerialization.data(withJSONObject: settings).write(to: url)
        return url
    }

    func testPlaintextKeyMigratesAndSurvivesSettingsReload() throws {
        let url = try legacySettingsFile()
        let secrets = RegressionSecrets()
        let defaults = UserDefaults(suiteName: "MacOptimizerRegression.\(UUID().uuidString)")!
        let store = AIProviderSettingsStore(settingsURL: url, defaults: defaults, secrets: secrets)
        XCTAssertFalse(store.credentialStorageFailed)
        XCTAssertEqual(secrets.values["ai.openAI.api-key"], "fixture-secret")
        let json = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("fixture-secret"))
        let reloaded = AIProviderSettingsStore(settingsURL: url, defaults: defaults, secrets: secrets)
        XCTAssertEqual(reloaded.configuration().apiKey, "fixture-secret")
        try reloaded.save(provider: .openAI, baseURL: "https://example.invalid", apiKey: "replacement", model: "fixture")
        XCTAssertEqual(secrets.values["ai.openAI.api-key"], "replacement")
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("replacement"))
    }

    func testFailedKeychainMigrationRetainsOriginalFile() throws {
        let url = try legacySettingsFile()
        let original = try Data(contentsOf: url)
        let secrets = RegressionSecrets()
        secrets.failWrites = true
        let defaults = UserDefaults(suiteName: "MacOptimizerRegression.\(UUID().uuidString)")!
        let store = AIProviderSettingsStore(settingsURL: url, defaults: defaults, secrets: secrets)
        XCTAssertTrue(store.credentialStorageFailed)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(store.configuration().apiKey, "fixture-secret")
    }

    func testNativeMetricsStayWithinValidRanges() {
        let sampler = SystemMetricsSampler()
        _ = sampler.cpuUsage()
        if let cpu = sampler.cpuUsage() { XCTAssertTrue((0...1).contains(cpu)) }
        if let traffic = sampler.networkUsage() {
            XCTAssertGreaterThanOrEqual(traffic.download, 0)
            XCTAssertGreaterThanOrEqual(traffic.upload, 0)
        }
    }
}
