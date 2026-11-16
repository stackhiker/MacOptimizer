import XCTest
import SQLite3
@testable import AppUninstaller

private actor PrivacyScanGate {
    private(set) var calls = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        calls += 1
        await withCheckedContinuation { continuation = $0 }
    }
    func open() { continuation?.resume(); continuation = nil }
}

final class PrivacyCleanupScopeRegressionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivacyScopeTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try FileManager.default.removeItem(at: root) }
    }

    private func execute(_ url: URL, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw PrivacyCleanupError.sqlite("fixture open") }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw PrivacyCleanupError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func value(_ url: URL, _ query: String) throws -> Int {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw PrivacyCleanupError.sqlite("fixture read")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw PrivacyCleanupError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw PrivacyCleanupError.sqlite("fixture query") }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func count(_ url: URL, _ table: String) throws -> Int {
        try value(url, "SELECT COUNT(*) FROM \(table)")
    }

    private func history(_ name: String = "History") throws -> URL {
        let url = root.appendingPathComponent(name)
        try execute(url, """
            CREATE TABLE urls(id INTEGER PRIMARY KEY, url TEXT, visit_count INTEGER, typed_count INTEGER, last_visit_time INTEGER);
            CREATE TABLE visits(id INTEGER PRIMARY KEY, url INTEGER);
            CREATE TABLE keyword_search_terms(url_id INTEGER, term TEXT);
            CREATE TABLE downloads(id INTEGER PRIMARY KEY, target_path TEXT);
            CREATE TABLE downloads_url_chains(id INTEGER, url TEXT);
            INSERT INTO urls VALUES(1,'https://visited.invalid',3,1,42),(2,'https://search.invalid',2,1,43);
            INSERT INTO visits VALUES(1,1),(2,2);
            INSERT INTO keyword_search_terms VALUES(2,'keep this search');
            INSERT INTO downloads VALUES(1,'keep.bin');
            INSERT INTO downloads_url_chains VALUES(1,'https://download.invalid');
            """)
        return url
    }

    private func item(_ url: URL, scope: PrivacyDatabaseScope?, selected: Bool = true,
                      browser: BrowserType = .chrome) -> PrivacyItem {
        PrivacyItem(browser: browser, type: scope == .chromeDownloadHistory ? .downloads : .history,
                    path: url, size: 4096, displayPath: "Fixture", isSelected: selected, databaseScope: scope)
    }

    private func service(running: @escaping () -> [BrowserType] = { [] },
                         quit: @escaping () async -> Bool = { XCTFail("Unexpected browser quit"); return false },
                         trash: @escaping (URL) throws -> Void = { _ in XCTFail("Unexpected file deletion") }) -> PrivacyScannerService {
        PrivacyScannerService(runningBrowsers: running, requestBrowserQuit: quit, trashItem: trash, validatePath: { _ in true })
    }

    func testDownloadSelectionPreservesBrowsingAndSearches() throws {
        let url = try history()
        try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeDownloadHistory])
        XCTAssertEqual(try count(url, "downloads"), 0)
        XCTAssertEqual(try count(url, "downloads_url_chains"), 0)
        XCTAssertEqual(try count(url, "visits"), 2)
        XCTAssertEqual(try count(url, "urls"), 2)
        XCTAssertEqual(try count(url, "keyword_search_terms"), 1)
    }

    func testBrowsingSelectionPreservesSearchReferencesAndDownloads() throws {
        let url = try history()
        try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeBrowsingHistory])
        XCTAssertEqual(try count(url, "visits"), 0)
        XCTAssertEqual(try count(url, "urls"), 1)
        XCTAssertEqual(try value(url, "SELECT id FROM urls"), 2)
        XCTAssertEqual(try value(url, "SELECT visit_count + typed_count + last_visit_time FROM urls"), 0)
        XCTAssertEqual(try count(url, "keyword_search_terms"), 1)
        XCTAssertEqual(try count(url, "downloads"), 1)
    }

    func testSearchSelectionPreservesBrowsingAndDownloads() throws {
        let url = try history()
        try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeSearchQueries])
        XCTAssertEqual(try count(url, "keyword_search_terms"), 0)
        XCTAssertEqual(try count(url, "visits"), 2)
        XCTAssertEqual(try count(url, "urls"), 2)
        XCTAssertEqual(try count(url, "downloads"), 1)
    }

    func testCombinedSelectionClearsOnlyRequestedTables() throws {
        let url = try history()
        try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeBrowsingHistory, .chromeSearchQueries])
        XCTAssertEqual(try count(url, "visits"), 0)
        XCTAssertEqual(try count(url, "urls"), 0)
        XCTAssertEqual(try count(url, "keyword_search_terms"), 0)
        XCTAssertEqual(try count(url, "downloads"), 1)
    }

    func testMissingRequiredTableRollsBackEarlierChanges() throws {
        let url = try history()
        try execute(url, "DROP TABLE downloads")
        XCTAssertThrowsError(try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeBrowsingHistory, .chromeDownloadHistory]))
        XCTAssertEqual(try count(url, "visits"), 2)
        XCTAssertEqual(try count(url, "urls"), 2)
        XCTAssertEqual(try count(url, "downloads_url_chains"), 1)
    }

    func testSQLFailureRollsBackAllSelectedScopes() throws {
        let url = try history()
        try execute(url, "CREATE TRIGGER fail_urls BEFORE DELETE ON urls BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
        XCTAssertThrowsError(try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeBrowsingHistory, .chromeSearchQueries]))
        XCTAssertEqual(try count(url, "keyword_search_terms"), 1)
        XCTAssertEqual(try count(url, "visits"), 2)
    }

    func testCookieDomainIsBoundAndUnselectedDomainsRemain() throws {
        let url = root.appendingPathComponent("Cookies")
        try execute(url, "CREATE TABLE cookies(host_key TEXT); INSERT INTO cookies VALUES('keep.invalid'),('a'' OR 1=1 --')")
        try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeCookies(domain: "a' OR 1=1 --")])
        XCTAssertEqual(try count(url, "cookies"), 1)
        XCTAssertEqual(try value(url, "SELECT COUNT(*) FROM cookies WHERE host_key='keep.invalid'"), 1)
    }

    func testLockedDatabaseFailsWithoutChangingRecords() throws {
        let url = try history()
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &lock), SQLITE_OK)
        defer { sqlite3_exec(lock, "ROLLBACK", nil, nil, nil); sqlite3_close(lock) }
        XCTAssertEqual(sqlite3_exec(lock, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeDownloadHistory]))
        XCTAssertEqual(try count(url, "downloads"), 1)
    }

    func testMissingDatabaseIsNotCreated() {
        let url = root.appendingPathComponent("absent")
        XCTAssertThrowsError(try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeDownloadHistory]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSymlinkDatabaseIsRejected() throws {
        let target = try history()
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try PrivacyDatabaseCleanup.clean(at: link, scopes: [.chromeDownloadHistory]))
        XCTAssertEqual(try count(target, "downloads"), 1)
    }

    func testCancellationInterruptsLargeDeleteAndRollsBack() throws {
        let url = try history()
        try execute(url, "WITH RECURSIVE n(x) AS (SELECT 3 UNION ALL SELECT x+1 FROM n WHERE x<10000) INSERT INTO visits SELECT x,1 FROM n")
        try execute(url, "CREATE TRIGGER visits_no_truncate AFTER DELETE ON visits BEGIN SELECT 1; END")
        var checks = 0
        XCTAssertThrowsError(try PrivacyDatabaseCleanup.clean(at: url, scopes: [.chromeBrowsingHistory], shouldCancel: {
            checks += 1
            return checks > 30
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertGreaterThan(checks, 30)
        XCTAssertEqual(try count(url, "visits"), 10000)
        XCTAssertEqual(try count(url, "urls"), 2)
    }

    @MainActor
    func testServiceRetainsUnselectedItemsSharingSameDatabase() async throws {
        let url = try history()
        let scanner = service()
        let browsing = item(url, scope: .chromeBrowsingHistory, selected: false)
        let download = item(url, scope: .chromeDownloadHistory)
        let search = item(url, scope: .chromeSearchQueries, selected: false)
        scanner.privacyItems = [browsing, download, search]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.cleaned, 0, "In-place SQL must not claim the database's full size as reclaimed")
        XCTAssertEqual(Set(scanner.privacyItems.map(\.id)), Set([browsing.id, search.id]))
        XCTAssertEqual(scanner.completedCleanupCount, 1)
        XCTAssertEqual(scanner.cleanedDatabaseCount, 1)
        XCTAssertEqual(try count(url, "visits"), 2)
    }

    @MainActor
    func testServiceSQLFailureIsReportedAndSelectionRemains() async throws {
        let url = try history()
        try execute(url, "DROP TABLE downloads")
        let scanner = service()
        let selected = item(url, scope: .chromeDownloadHistory)
        scanner.privacyItems = [selected]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(scanner.completedCleanupCount, 0)
        XCTAssertEqual(scanner.privacyItems.map(\.id), [selected.id])
        XCTAssertEqual(scanner.lastCleanupFailures.count, 1)
    }

    @MainActor
    func testIgnoreKeepsRunningBrowserDataAndNeverRequestsQuit() async throws {
        let url = try history()
        var quitCalls = 0
        let scanner = service(running: { [.chrome] }, quit: { quitCalls += 1; return true })
        scanner.privacyItems = [item(url, scope: .chromeDownloadHistory)]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(quitCalls, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(try count(url, "downloads"), 1)
        XCTAssertEqual(scanner.privacyItems.count, 1)
    }

    @MainActor
    func testExplicitQuitRequestsOnlyInjectedNormalExit() async {
        var quitCalls = 0
        let scanner = service(quit: { quitCalls += 1; return false })
        let quit = await scanner.closeBrowsers()
        XCTAssertFalse(quit)
        XCTAssertEqual(quitCalls, 1)
    }

    @MainActor
    func testBrowserActivityIsRecheckedForEachDatabase() async throws {
        let first = try history("A")
        let second = try history("B")
        var activityChecks = 0
        let scanner = service(running: { activityChecks += 1; return activityChecks == 1 ? [] : [.chrome] })
        scanner.privacyItems = [item(first, scope: .chromeDownloadHistory), item(second, scope: .chromeDownloadHistory)]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(try count(first, "downloads"), 0)
        XCTAssertEqual(try count(second, "downloads"), 1)
    }

    @MainActor
    func testStopCleanupRetainsEveryUnattemptedItem() async throws {
        let first = root.appendingPathComponent("A")
        let second = root.appendingPathComponent("B")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        var scanner: PrivacyScannerService!
        scanner = service(trash: { url in
            try FileManager.default.moveItem(at: url, to: self.root.appendingPathComponent("fixture-trash"))
            scanner.stopCleaning()
        })
        scanner.privacyItems = [item(first, scope: nil, browser: .system), item(second, scope: nil, browser: .system)]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(result.failed, 0)
        XCTAssertTrue(scanner.cleanupWasCancelled)
        XCTAssertEqual(scanner.privacyItems.map(\.path), [second])
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    @MainActor
    func testCancelledCleanupDoesNotReportCompletionOrModifyDatabase() async throws {
        let url = try history()
        let scanner = service()
        scanner.privacyItems = [item(url, scope: .chromeDownloadHistory)]
        let result = await scanner.cleanSelected(shouldCancel: { true })
        XCTAssertTrue(scanner.cleanupWasCancelled)
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(scanner.completedCleanupCount, 0)
        XCTAssertEqual(scanner.privacyItems.count, 1)
        XCTAssertEqual(try count(url, "downloads"), 1)
    }

    @MainActor
    func testMissingScopeAndFirefoxMixedDatabaseNeverFallBackToTrash() async throws {
        let chrome = try history()
        let firefox = root.appendingPathComponent("places.sqlite")
        try execute(firefox, "CREATE TABLE moz_bookmarks(id INTEGER); INSERT INTO moz_bookmarks VALUES(1)")
        let scanner = service()
        scanner.privacyItems = [item(chrome, scope: nil), item(firefox, scope: nil, browser: .firefox)]
        let result = await scanner.cleanSelected()
        XCTAssertEqual(result.failed, 2)
        XCTAssertEqual(scanner.privacyItems.count, 2)
        XCTAssertEqual(try count(firefox, "moz_bookmarks"), 1)
    }

    @MainActor
    func testStoppedScanRetainsOwnershipAndDropsLateResults() async throws {
        let gate = PrivacyScanGate()
        let late = item(root.appendingPathComponent("late"), scope: nil, selected: false)
        let scanner = PrivacyScannerService(runningBrowsers: { [] }, scanStage: { stage in
            if stage == 0 { await gate.wait(); return [late] }
            return []
        })
        let task = Task { await scanner.scanAll() }
        for _ in 0..<200 {
            if await gate.calls > 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        scanner.stopScan()
        XCTAssertTrue(scanner.isScanning)
        await scanner.scanAll()
        let calls = await gate.calls
        XCTAssertEqual(calls, 1)
        await gate.open()
        await task.value
        XCTAssertFalse(scanner.isScanning)
        XCTAssertFalse(scanner.hasScanned)
        XCTAssertTrue(scanner.privacyItems.isEmpty)
    }

    @MainActor
    func testScanPublishesAccessIssuesWithoutSelectingResults() async {
        var scanner: PrivacyScannerService!
        scanner = PrivacyScannerService(runningBrowsers: { [] }, scanStage: { stage in
            if stage == 0 { scanner.recordScanIssue(at: self.root, message: "fixture access denied") }
            return []
        })
        await scanner.scanAll()
        XCTAssertTrue(scanner.hasScanned)
        XCTAssertEqual(scanner.lastScanIssues.count, 1)
        XCTAssertTrue(scanner.privacyItems.isEmpty)
    }
}
