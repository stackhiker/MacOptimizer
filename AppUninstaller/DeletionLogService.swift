import Foundation
import AppKit

// MARK: - 废纸篓记录模型（用于跟踪删除的文件以便恢复）
struct TrashRecord: Codable, Identifiable {
    let id: UUID
    let originalPath: String      // 原始路径
    let trashPath: String?        // 废纸篓中的路径
    let fileName: String          // 文件名
    let size: Int64               // 文件大小
    let deletionDate: Date        // 删除时间
    let category: String          // 删除来源 (SmartClean, DeepClean, etc.)
    var isRestored: Bool          // 是否已恢复
    
    init(originalPath: String, trashPath: String?, size: Int64, category: String) {
        self.id = UUID()
        self.originalPath = originalPath
        self.trashPath = trashPath
        self.fileName = URL(fileURLWithPath: originalPath).lastPathComponent
        self.size = size
        self.deletionDate = Date()
        self.category = category
        self.isRestored = false
    }
}

struct DeletionFailureRecord: Codable {
    let date: Date
    let category: String
    let failure: RemovalFailure
}

// MARK: - 删除日志服务
/// 记录删除的文件，支持恢复到原位置
// Journal state is protected by logLock; published state is only mutated on main.
final class DeletionLogService: ObservableObject, @unchecked Sendable {
    static let shared = DeletionLogService()
    
    private let fileManager = FileManager.default
    private let logDirectory: URL
    private let dateFormatter: ISO8601DateFormatter
    private let logLock = NSRecursiveLock()
    private let restoreQueue = DispatchQueue(label: "com.macoptimizer.restore", qos: .utility)
    @Published private(set) var lastError: String?
    private var knownRecords: [UUID: TrashRecord] = [:]
    private var restoredIDs = Set<UUID>()
    private let moveToTrash: (URL) throws -> URL?
    
    @Published var deletionRecords: [TrashRecord] = []
    
    // 日志保留天数
    private let retentionDays: Int = 30
    
    init(logDirectory: URL? = nil, moveToTrash: @escaping (URL) throws -> URL? = { url in
        var destination: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
        return destination as URL?
    }) {
        // 日志存储目录: ~/Library/Application Support/MacOptimizer/deletion_logs/
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.logDirectory = logDirectory ?? appSupport.appendingPathComponent("MacOptimizer/deletion_logs")
        self.moveToTrash = moveToTrash
        
        // 创建目录
        try? fileManager.createDirectory(at: self.logDirectory, withIntermediateDirectories: true)
        
        dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        // 加载今天的日志
        loadAllLogs()
        
        // 清理过期日志
        cleanupOldLogs()
    }
    
    // MARK: - 公共 API
    
    /// 安全删除文件并记录日志（支持从废纸篓恢复）
    /// - Parameters:
    ///   - url: 要删除的文件 URL
    ///   - category: 删除来源类别
    /// - Returns: 删除是否成功
    @discardableResult
    func logAndDelete(at url: URL, category: String = "SmartClean") -> Bool {
        do {
            try trashItem(at: url, category: category)
            return true
        } catch {
            logFailure(RemovalFailure(path: url, error: error), category: category)
            return false
        }
    }

    /// Records a successful move and preserves the original error for callers
    /// that need to report individual failures. Callers record caught failures
    /// with logFailure, or use the Boolean logAndDelete convenience method.
    func trashItem(at url: URL, category: String = "SmartClean", sizeHint: Int64? = nil) throws {
        let originalPath = url.path
        
        let size = sizeHint ?? CleanupFileSystem.logicalSize(at: url)

        // 使用 trashItem 并获取废纸篓中的新路径
        let trashURL = try moveToTrash(url)

        let trashPath = trashURL?.path

        // 创建删除记录
        let record = TrashRecord(
            originalPath: originalPath,
            trashPath: trashPath,
            size: size,
            category: category
        )

        logLock.lock()
        defer { logLock.unlock() }
        knownRecords[record.id] = record
        appendLine(record, prefix: "deletions")
        // Enqueue publication while holding the same lock as loadAllLogs, so
        // a refresh cannot publish this record and then receive a duplicate append.
        DispatchQueue.main.async {
            if !self.deletionRecords.contains(where: { $0.id == record.id }) {
                self.deletionRecords.insert(record, at: 0)
            }
        }

        print("[DeletionLog] ✅ Logged deletion: \(originalPath) -> \(trashPath ?? "unknown")")
    }

    func logFailure(_ failure: RemovalFailure, category: String) {
        appendRecord(DeletionFailureRecord(date: Date(), category: category, failure: failure), prefix: "failures")
        print("[DeletionLog] ❌ Failed to delete: \(failure.path.path) - \(failure.message) (\(failure.errorDomain) \(failure.errorCode))")
    }
    
    /// 恢复文件到原位置
    /// - Parameter record: 删除记录
    /// - Returns: 恢复是否成功
    func restore(_ record: TrashRecord) -> Bool {
        do { try restoreChecked(record); return true }
        catch { DispatchQueue.main.async { self.lastError = error.localizedDescription }; return false }
    }

    func restoreRecord(_ record: TrashRecord) async throws {
        try await withCheckedThrowingContinuation { continuation in
            restoreQueue.async {
                do { try self.restoreChecked(record); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func restoreChecked(_ record: TrashRecord) throws {
        logLock.lock()
        defer { logLock.unlock() }
        guard let authoritative = knownRecords[record.id], !authoritative.isRestored,
              !restoredIDs.contains(record.id), !record.isRestored,
              authoritative.originalPath == record.originalPath,
              authoritative.trashPath == record.trashPath,
              let trashPath = authoritative.trashPath else {
            throw CocoaError(.fileNoSuchFile)
        }
        let trashURL = URL(fileURLWithPath: trashPath)
        let original = URL(fileURLWithPath: record.originalPath)
        // Never move aside or overwrite a file created since the cleanup.
        guard !fileManager.fileExists(atPath: original.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        guard fileManager.fileExists(atPath: trashURL.path) else { throw CocoaError(.fileNoSuchFile) }
        try fileManager.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: trashURL, to: original)
        restoredIDs.insert(record.id)
        var restoredRecord = authoritative
        restoredRecord.isRestored = true
        knownRecords[record.id] = restoredRecord
        let persisted = appendLine(RestorationRecord(id: record.id), prefix: "restorations")
        DispatchQueue.main.async {
            if let i = self.deletionRecords.firstIndex(where: { $0.id == record.id }) {
                self.deletionRecords[i].isRestored = true
            }
            if persisted { self.lastError = nil }
        }
        if !persisted {
            throw NSError(domain: "RecoveryJournal", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "文件已恢复，但恢复记录未能保存。请检查磁盘空间或目录权限。 / File restored, but its recovery record could not be saved."])
        }
    }

    private struct RestorationRecord: Codable { let id: UUID }

    /// 获取可恢复的文件列表
    func getRestorableRecords() -> [TrashRecord] {
        return deletionRecords.filter { record in
            guard let trashPath = record.trashPath else { return false }
            return !record.isRestored && fileManager.fileExists(atPath: trashPath)
        }
    }
    
    /// 加载所有日志（最近 N 天）
    func loadAllLogs(days: Int = 30) {
        logLock.lock()
        defer { logLock.unlock() }
        var all: [TrashRecord] = []
        var restored = Set<UUID>()
        for dayOffset in 0..<max(0, min(days, retentionDays)) {
            guard let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let day = dateFormatter.string(from: date)
            if let data = try? Data(contentsOf: logDirectory.appendingPathComponent("deletions_\(day).json")),
               let legacy = try? JSONDecoder().decode([TrashRecord].self, from: data) { all += legacy }
            all += readLines(TrashRecord.self, file: "deletions_\(day).jsonl")
            restored.formUnion(readLines(RestorationRecord.self, file: "restorations_\(day).jsonl").map(\.id))
        }
        let result = all.map { record -> TrashRecord in
            var copy = record
            copy.isRestored = copy.isRestored || restored.contains(copy.id)
            return copy
        }.sorted { $0.deletionDate > $1.deletionDate }
        restoredIDs.formUnion(restored)
        for record in result {
            if restoredIDs.contains(record.id) {
                var copy = record; copy.isRestored = true; knownRecords[record.id] = copy
            } else { knownRecords[record.id] = record }
        }
        let published = knownRecords.values.sorted { $0.deletionDate > $1.deletionDate }
        DispatchQueue.main.async { self.deletionRecords = published }
    }

    private func readLines<T: Decodable>(_ type: T.Type, file: String) -> [T] {
        guard let data = try? Data(contentsOf: logDirectory.appendingPathComponent(file)) else { return [] }
        return data.split(separator: 10).compactMap { try? JSONDecoder().decode(type, from: Data($0)) }
    }

    // One append per successful move instead of re-reading/re-encoding the day.
    @discardableResult private func appendLine<T: Encodable>(_ record: T, prefix: String) -> Bool {
        logLock.lock()
        defer { logLock.unlock() }
        let file = logDirectory.appendingPathComponent("\(prefix)_\(dateFormatter.string(from: Date())).jsonl")
        do {
            var data = try JSONEncoder().encode(record)
            data.append(10)
            if !fileManager.fileExists(atPath: file.path) { fileManager.createFile(atPath: file.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
            return true
        } catch {
            DispatchQueue.main.async { self.lastError = error.localizedDescription }
            return false
        }
    }

    // MARK: - 私有方法
    
    private func loadTodayLog() {
        let dateString = dateFormatter.string(from: Date())
        let logFile = logDirectory.appendingPathComponent("deletions_\(dateString).json")
        
        if let data = try? Data(contentsOf: logFile),
           let records = try? JSONDecoder().decode([TrashRecord].self, from: data) {
            DispatchQueue.main.async {
                self.deletionRecords = records
            }
        }
    }
    
    private func saveRecord(_ record: TrashRecord) {
        appendRecord(record, prefix: "deletions")
    }

    private func appendRecord<T: Codable>(_ record: T, prefix: String) {
        logLock.lock()
        defer { logLock.unlock() }
        let dateString = dateFormatter.string(from: Date())
        let logFile = logDirectory.appendingPathComponent("\(prefix)_\(dateString).json")
        
        // 读取现有记录
        var records: [T] = []
        if let data = try? Data(contentsOf: logFile),
           let existingRecords = try? JSONDecoder().decode([T].self, from: data) {
            records = existingRecords
        }
        
        // 添加新记录
        records.append(record)
        
        // 保存
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: logFile, options: .atomic)
        } catch {
            print("[DeletionLog] ❌ Failed to save log: \(error.localizedDescription)")
        }
    }
    
    private func cleanupOldLogs() {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -retentionDays, to: Date()) else { return }
        
        if let files = try? fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: [.creationDateKey]) {
            for file in files {
                if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                   let creationDate = attrs.creationDate,
                   creationDate < cutoffDate {
                    try? fileManager.removeItem(at: file)
                    print("[DeletionLog] 🗑️ Cleaned up old log: \(file.lastPathComponent)")
                }
            }
        }
    }
    
    private func calculateSize(at url: URL) -> Int64 {
        var totalSize: Int64 = 0
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }
        return totalSize
    }
}

// MARK: - 便捷扩展
extension FileManager {
    /// 安全删除文件并记录日志（使用 DeletionLogService）
    func safeTrashItem(at url: URL, category: String = "General") -> Bool {
        return DeletionLogService.shared.logAndDelete(at: url, category: category)
    }
}
