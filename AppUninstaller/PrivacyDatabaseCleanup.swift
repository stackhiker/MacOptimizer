import Foundation
import SQLite3

/// A selection describes records, not merely the SQLite file that contains them.
enum PrivacyDatabaseScope: Hashable, Sendable {
    case chromeBrowsingHistory
    case chromeDownloadHistory
    case chromeSearchQueries
    case chromeCookies(domain: String?)
    case chromeAutofill
    case safariHistory

    fileprivate var databaseKind: Int {
        switch self {
        case .chromeBrowsingHistory, .chromeDownloadHistory, .chromeSearchQueries: return 0
        case .chromeCookies: return 1
        case .chromeAutofill: return 2
        case .safariHistory: return 3
        }
    }
}

enum PrivacyCleanupError: LocalizedError {
    case unsafePath
    case missingScope
    case runningBrowser
    case unsupportedMixedDatabase
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .unsafePath: return "文件位置已变化或受到保护，请重新扫描。 / The path changed or is protected; scan again."
        case .missingScope: return "未确定数据库清理范围，请重新扫描。 / Database selection is unavailable; scan again."
        case .runningBrowser: return "浏览器仍在运行，项目已保留。请保存工作并退出后重试。 / Browser is running; save your work, quit it, and retry."
        case .unsupportedMixedDatabase: return "此数据库同时包含书签等数据，请在 Firefox 中清除浏览记录。 / Clear history in Firefox to preserve its shared bookmark database."
        case .sqlite(let message): return "数据库未完成清理：\(message) / Database cleanup did not complete."
        }
    }
}

/// Writes only existing, regular databases. Every requested group is atomic;
/// missing tables, locks, cancellation, and SQL failures roll the group back.
enum PrivacyDatabaseCleanup {
    private final class CancellationContext {
        let shouldCancel: () -> Bool
        init(_ shouldCancel: @escaping () -> Bool) { self.shouldCancel = shouldCancel }
    }

    @discardableResult
    static func clean(at url: URL, scopes: Set<PrivacyDatabaseScope>,
                      shouldCancel: @escaping () -> Bool = { Task.isCancelled }) throws -> Int {
        guard !scopes.isEmpty, Set(scopes.map(\.databaseKind)).count == 1 else {
            throw PrivacyCleanupError.missingScope
        }
        if shouldCancel() { throw CancellationError() }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw PrivacyCleanupError.unsafePath
        }

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard openResult == SQLITE_OK, let database = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            if let handle { sqlite3_close(handle) }
            throw PrivacyCleanupError.sqlite(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 250)
        let context = CancellationContext(shouldCancel)
        sqlite3_progress_handler(database, 100, { rawContext in
            guard let rawContext else { return 0 }
            let context = Unmanaged<CancellationContext>.fromOpaque(rawContext).takeUnretainedValue()
            return context.shouldCancel() ? 1 : 0
        }, Unmanaged.passUnretained(context).toOpaque())
        var committed = false
        defer {
            sqlite3_progress_handler(database, 0, nil, nil)
            if !committed { sqlite3_exec(database, "ROLLBACK", nil, nil, nil) }
            withExtendedLifetime(context) {}
        }

        func execute(_ sql: String, argument: String? = nil) throws {
            if shouldCancel() { throw CancellationError() }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw PrivacyCleanupError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }
            if let argument {
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                guard sqlite3_bind_text(statement, 1, argument, -1, transient) == SQLITE_OK else {
                    throw PrivacyCleanupError.sqlite(String(cString: sqlite3_errmsg(database)))
                }
            }
            guard sqlite3_step(statement) == SQLITE_DONE else {
                if shouldCancel() { throw CancellationError() }
                throw PrivacyCleanupError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }

        func strings(_ query: String, column: Int32 = 0) throws -> Set<String> {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
                throw PrivacyCleanupError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(statement) }
            var values = Set<String>()
            while true {
                if shouldCancel() { throw CancellationError() }
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return values }
                guard result == SQLITE_ROW else {
                    throw PrivacyCleanupError.sqlite(String(cString: sqlite3_errmsg(database)))
                }
                if let text = sqlite3_column_text(statement, column) { values.insert(String(cString: text)) }
            }
        }

        try execute("BEGIN IMMEDIATE")
        let tables = try strings("SELECT name FROM sqlite_master WHERE type = 'table'")
        let initialChanges = sqlite3_total_changes(database)

        if scopes.contains(.chromeSearchQueries) {
            try execute("DELETE FROM keyword_search_terms")
        }
        if scopes.contains(.chromeBrowsingHistory) {
            try execute("DELETE FROM visits")
            if tables.contains("visit_source") { try execute("DELETE FROM visit_source") }
            if tables.contains("keyword_search_terms") && !scopes.contains(.chromeSearchQueries) {
                // Search rows refer to urls.id. Preserve those URLs while clearing
                // only their browsing counters; an unselected search must survive.
                try execute("DELETE FROM urls WHERE id NOT IN (SELECT url_id FROM keyword_search_terms)")
                let columns = try strings("PRAGMA table_info(urls)", column: 1)
                let counters = ["visit_count", "typed_count", "last_visit_time"].filter { columns.contains($0) }
                if !counters.isEmpty {
                    try execute("UPDATE urls SET " + counters.map { "\($0) = 0" }.joined(separator: ", "))
                }
            } else {
                try execute("DELETE FROM urls")
            }
        }
        if scopes.contains(.chromeDownloadHistory) {
            if tables.contains("downloads_url_chains") { try execute("DELETE FROM downloads_url_chains") }
            try execute("DELETE FROM downloads")
        }
        let cookieScopes = scopes.filter { if case .chromeCookies = $0 { return true }; return false }
        if cookieScopes.contains(.chromeCookies(domain: nil)) {
            try execute("DELETE FROM cookies")
        } else {
            for scope in cookieScopes {
                if case .chromeCookies(let domain?) = scope {
                    try execute("DELETE FROM cookies WHERE host_key = ?", argument: domain)
                }
            }
        }
        if scopes.contains(.chromeAutofill) {
            try execute("DELETE FROM autofill")
            if tables.contains("autofill_profiles") { try execute("DELETE FROM autofill_profiles") }
        }
        if scopes.contains(.safariHistory) {
            try execute("DELETE FROM history_visits")
            try execute("DELETE FROM history_items")
        }

        if shouldCancel() { throw CancellationError() }
        try execute("COMMIT")
        committed = true
        // Do not VACUUM or claim the whole database as reclaimed disk space.
        return Int(sqlite3_total_changes(database) - initialChanges)
    }
}
