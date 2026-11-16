import SwiftUI

struct RecoveryCenterView: View {
    @ObservedObject private var journal = DeletionLogService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var restoring: UUID?
    @State private var errorMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.text("清理历史与恢复", "Cleanup History & Recovery")).font(.title2.bold())
            Text(loc.text("最近 30 天移入废纸篓的记录。清空废纸篓后无法恢复；原位置已有同名文件时会保留双方。", "Trash records from the last 30 days. Emptied Trash cannot be restored. Existing destination files are never overwritten."))
                .font(.caption).foregroundColor(.secondary)
            if let error = journal.lastError { Text(error).font(.caption).foregroundColor(.orange) }
            if journal.deletionRecords.isEmpty {
                Text(loc.text("暂无清理记录", "No cleanup history")).foregroundColor(.secondary)
            }
            List(journal.deletionRecords.prefix(500)) { record in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(record.fileName).font(.headline).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: record.size, countStyle: .file)).font(.caption)
                        Button(record.isRestored ? loc.text("已恢复", "Restored") : loc.text("恢复", "Restore")) {
                            restoring = record.id
                            Task {
                                do { try await journal.restoreRecord(record) }
                                catch { errorMessage = error.localizedDescription }
                                restoring = nil
                            }
                        }.disabled(record.isRestored || record.trashPath == nil || restoring != nil)
                    }
                    Text(record.originalPath).font(.caption).foregroundColor(.secondary).lineLimit(2).textSelection(.enabled)
                    HStack {
                        Text(record.category)
                        Text(record.deletionDate, style: .date)
                        Text(record.deletionDate, style: .time)
                    }.font(.caption2).foregroundColor(.secondary)
                }.padding(.vertical, 5)
            }.listStyle(.plain)
        }.padding(22)
        .task { await Task.detached(priority: .utility) { DeletionLogService.shared.loadAllLogs() }.value }
        .alert(loc.text("未能恢复", "Restore failed"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button(loc.text("确定", "OK")) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

struct PermissionCoverageView: View {
    struct Entry: Identifiable { var id: String { path }; let path: String; let readable: Bool; let detail: String }
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var entries: [Entry] = []
    @State private var loading = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.text("访问权限与扫描范围", "Access & Scan Coverage")).font(.title2.bold())
            Text(loc.text("检查常用目录能否读取。未授权、跳过或停止的范围不代表已经清理或安全。", "Checks access to common folders. Inaccessible, skipped or stopped scopes are not clean or security verdicts."))
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Button(loc.text("重新检查", "Check Again")) { Task { await refresh() } }.disabled(loading)
                Button(loc.text("打开磁盘访问设置", "Open Disk Access Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                }
                if loading { ProgressView().controlSize(.small) }
            }
            List(entries) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    Label(entry.path, systemImage: entry.readable ? "checkmark.circle" : "exclamationmark.circle")
                    Text(entry.readable ? loc.text("可读取目录", "Directory is readable") : entry.detail)
                        .font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 5)
            }.listStyle(.plain)
        }.padding(22).task { await refresh() }
    }
    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true
        entries = await Task.detached(priority: .utility) {
            ["Desktop", "Documents", "Downloads", "Library/Mail", "Library/Messages", "Library/Safari"].map { relative in
                let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative)
                do {
                    _ = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    return Entry(path: url.path, readable: true, detail: "")
                } catch { return Entry(path: url.path, readable: false, detail: error.localizedDescription) }
            }
        }.value
        loading = false
    }
}
