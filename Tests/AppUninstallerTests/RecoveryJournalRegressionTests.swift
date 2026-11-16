import XCTest
@testable import AppUninstaller

/// All moves stay inside a disposable fixture. The real Trash API is never used.
final class RecoveryJournalRegressionTests: XCTestCase {
    private var root: URL!
    private var logs: URL { root.appendingPathComponent("logs") }
    private var trash: URL { root.appendingPathComponent("fixture-trash") }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("RecoveryJournalTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func makeJournal() -> DeletionLogService {
        let destination = trash
        return DeletionLogService(logDirectory: logs, moveToTrash: { source in
            let target = destination.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: target)
            return target
        })
    }

    @MainActor private func flushPublishedUpdates() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor private func trashFixture(_ name: String = "original.txt", journal: DeletionLogService) async throws -> TrashRecord {
        let original = root.appendingPathComponent(name)
        try Data("original".utf8).write(to: original)
        try journal.trashItem(at: original, category: "Fixture", sizeHint: 8)
        await flushPublishedUpdates()
        return try XCTUnwrap(journal.deletionRecords.first { $0.originalPath == original.path })
    }

    @MainActor func testConcurrentJournalAppendsSurviveRestartWithoutLostRecords() async throws {
        let journal = makeJournal()
        let originals = (0..<32).map { root.appendingPathComponent("file-\($0).txt") }
        for original in originals { try Data("fixture".utf8).write(to: original) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for original in originals {
                group.addTask { try journal.trashItem(at: original, category: "Fixture", sizeHint: 7) }
            }
            try await group.waitForAll()
        }
        let restarted = makeJournal()
        await flushPublishedUpdates()
        XCTAssertEqual(restarted.deletionRecords.count, originals.count)
        XCTAssertEqual(Set(restarted.deletionRecords.map(\.id)).count, originals.count)
        XCTAssertEqual(Set(restarted.deletionRecords.map(\.originalPath)), Set(originals.map(\.path)))
    }

    @MainActor func testLegacyJSONArrayAndNewJSONLinesAreBothLoaded() async throws {
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let legacy = TrashRecord(originalPath: root.appendingPathComponent("legacy.txt").path,
                                 trashPath: trash.appendingPathComponent("legacy.txt").path,
                                 size: 1, category: "Legacy")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let legacyFile = logs.appendingPathComponent("deletions_\(formatter.string(from: Date())).json")
        try JSONEncoder().encode([legacy]).write(to: legacyFile)
        let journal = makeJournal()
        let current = try await trashFixture(journal: journal)
        let restarted = makeJournal()
        await flushPublishedUpdates()
        XCTAssertEqual(Set(restarted.deletionRecords.map(\.id)), [legacy.id, current.id])
        XCTAssertEqual(try JSONDecoder().decode([TrashRecord].self, from: Data(contentsOf: legacyFile)).count, 1)
    }

    @MainActor func testRestoredJournalRejectsStaleRecordWhenTrashPathIsReusedAfterRestart() async throws {
        let journal = makeJournal()
        let stale = try await trashFixture(journal: journal)
        try await journal.restoreRecord(stale)
        try FileManager.default.moveItem(atPath: stale.originalPath, toPath: root.appendingPathComponent("kept-original.txt").path)
        let reusedSource = URL(fileURLWithPath: try XCTUnwrap(stale.trashPath))
        try Data("unrelated-new-file".utf8).write(to: reusedSource)

        let restarted = makeJournal()
        await flushPublishedUpdates()
        XCTAssertEqual(restarted.deletionRecords.first?.isRestored, true)
        do { try await restarted.restoreRecord(stale); XCTFail("An already restored ID must not be replayed") }
        catch { }
        XCTAssertEqual(try String(contentsOf: reusedSource), "unrelated-new-file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.originalPath))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("kept-original.txt")), "original")
    }

    @MainActor func testForgedUnknownRecordCannotMoveAnUnrelatedFile() async throws {
        let journal = makeJournal()
        let unrelated = root.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)
        let target = root.appendingPathComponent("forged-target.txt")
        let forged = TrashRecord(originalPath: target.path, trashPath: unrelated.path, size: 4, category: "Fixture")
        do { try await journal.restoreRecord(forged); XCTFail("An unregistered ID is not a restore capability") }
        catch { }
        XCTAssertEqual(try String(contentsOf: unrelated), "keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    @MainActor func testKnownIDWithAlteredSourceOrDestinationIsRejected() async throws {
        let journal = makeJournal()
        let record = try await trashFixture(journal: journal)
        let unrelated = root.appendingPathComponent("unrelated.txt")
        try Data("keep".utf8).write(to: unrelated)
        for key in ["trashPath", "originalPath"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
            object[key] = key == "trashPath" ? unrelated.path : root.appendingPathComponent("altered-target.txt").path
            let forged = try JSONDecoder().decode(TrashRecord.self, from: JSONSerialization.data(withJSONObject: object))
            do { try await journal.restoreRecord(forged); XCTFail("Altered \(key) must be rejected") }
            catch { }
        }
        XCTAssertEqual(try String(contentsOf: unrelated), "keep")
        XCTAssertEqual(try String(contentsOfFile: try XCTUnwrap(record.trashPath)), "original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.originalPath))
    }

    @MainActor func testConcurrentRestoreRequestsMoveOriginalExactlyOnce() async throws {
        let journal = makeJournal()
        let record = try await trashFixture(journal: journal)
        let successes = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do { try await journal.restoreRecord(record); return true }
                    catch { return false }
                }
            }
            var count = 0
            for await success in group { if success { count += 1 } }
            return count
        }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(try String(contentsOfFile: record.originalPath), "original")
        let restarted = makeJournal()
        await flushPublishedUpdates()
        XCTAssertEqual(restarted.deletionRecords.first?.isRestored, true)
    }

    func testFailureJournalsRemainCompatibleJSONArrays() throws {
        let journal = makeJournal()
        for name in ["first", "second"] {
            journal.logFailure(RemovalFailure(path: root.appendingPathComponent(name), error: CocoaError(.fileReadNoPermission)), category: "Fixture")
        }
        let files = try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
        let file = try XCTUnwrap(files.first { $0.lastPathComponent.hasPrefix("failures_") && $0.pathExtension == "json" })
        let failures = try JSONDecoder().decode([DeletionFailureRecord].self, from: Data(contentsOf: file))
        XCTAssertEqual(failures.map { $0.failure.path.lastPathComponent }, ["first", "second"])
    }
    @MainActor
    func testRefreshingDuringConcurrentMovesPublishesEachRecordOnce() async throws {
        let journal = makeJournal()
        let fixture = root!
        for index in 0..<24 { try Data([1]).write(to: fixture.appendingPathComponent("concurrent-\(index)")) }
        await Task.detached {
            DispatchQueue.concurrentPerform(iterations: 24) { index in
                try? journal.trashItem(at: fixture.appendingPathComponent("concurrent-\(index)"), category: "fixture", sizeHint: 1)
                journal.loadAllLogs()
            }
        }.value
        await flushPublishedUpdates()
        XCTAssertEqual(journal.deletionRecords.count, 24)
        XCTAssertEqual(Set(journal.deletionRecords.map(\.id)).count, 24)
    }
}
