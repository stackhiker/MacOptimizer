import CryptoKit
import Foundation

enum MacAgentTool: String, Codable, CaseIterable {
    case scanJunk = "scan_junk"
    case scanLargeFiles = "scan_large_files"
    case scanDuplicates = "scan_duplicates"
    case inspectStorage = "inspect_storage"
    case inspectSystem = "inspect_system"
    case inspectStartup = "inspect_startup"
    case listResults = "list_results"
    case prepareCleanup = "prepare_cleanup"
    case finish
}

struct MacAgentArguments: Codable {
    var minimumSizeMB: Int?
    var olderThanDays: Int?
}

struct MacAgentDecision: Decodable {
    let tool: MacAgentTool
    let arguments: MacAgentArguments?
    let message: String?
}

enum MacAgentFindingCategory: String, Sendable {
    case userCache
    case userLog
    case crashReport
    case savedState
    case systemCache
    case systemLog
    case largeFile
    case duplicateFile
    case startupItem
}

struct MacAgentFinding: Identifiable, Sendable {
    let id: UUID
    let path: String
    let category: MacAgentFindingCategory
    let size: Int64
    let modifiedAt: Date?

    init(path: String, category: MacAgentFindingCategory, size: Int64, modifiedAt: Date?) {
        self.id = UUID()
        self.path = path
        self.category = category
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

struct MacAgentToolReport: Sendable {
    let tool: MacAgentTool
    let findings: [MacAgentFinding]
    let facts: [String: String]

    var count: Int { findings.count }
    var bytes: Int64 { findings.reduce(0) { $0 + $1.size } }

    var modelSummary: String {
        let categories = Dictionary(grouping: findings, by: \.category)
            .map { key, values in
                "\(key.rawValue)=\(values.count) files/\(values.reduce(0) { $0 + $1.size }) bytes"
            }
            .sorted()
            .joined(separator: ", ")
        let factSummary = facts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", ")
        return "tool=\(tool.rawValue); total_files=\(count); total_bytes=\(bytes); categories=[\(categories)]; facts=[\(factSummary)]"
    }
}

struct MacAgentCleanupResult: Sendable {
    let cleanedCount: Int
    let cleanedBytes: Int64
    let failedCount: Int
    var failedPaths: Set<String> = []
}

@MainActor
final class MacMaintenanceAgentService: ObservableObject {
    static let shared = MacMaintenanceAgentService()

    @Published private(set) var lastReport: MacAgentToolReport?
    @Published private(set) var pendingCleanup: [MacAgentFinding] = []
    @Published private(set) var isCleaning = false

    private init() {}

    func execute(_ tool: MacAgentTool, arguments: MacAgentArguments?) async -> MacAgentToolReport {
        let report: MacAgentToolReport
        switch tool {
        case .scanJunk:
            let days = max(1, arguments?.olderThanDays ?? 3)
            report = await Task.detached(priority: .userInitiated) { Self.scanJunk(olderThanDays: days) }.value
        case .scanLargeFiles:
            let minimumMB = max(10, arguments?.minimumSizeMB ?? 100)
            report = await Task.detached(priority: .userInitiated) { Self.scanLargeFiles(minimumSizeMB: minimumMB) }.value
        case .scanDuplicates:
            report = await Task.detached(priority: .userInitiated) { Self.scanDuplicates() }.value
        case .inspectStorage:
            report = await Task.detached(priority: .userInitiated) { Self.inspectStorage() }.value
        case .inspectSystem:
            report = await Task.detached(priority: .userInitiated) { Self.inspectSystem() }.value
        case .inspectStartup:
            report = await Task.detached(priority: .userInitiated) { Self.inspectStartup() }.value
        case .listResults:
            report = lastReport ?? .init(tool: .listResults, findings: [], facts: ["state": "no_previous_scan"])
        case .prepareCleanup:
            guard !isCleaning else { return .init(tool: .prepareCleanup, findings: [], facts: ["state": "cleanup_in_progress"]) }
            let source: MacAgentToolReport
            if let lastReport {
                source = lastReport
            } else {
                source = await Task.detached(priority: .userInitiated) { Self.scanJunk(olderThanDays: 3) }.value
            }
            let safe = source.findings.filter { Self.isSafeCleanupFinding($0) }
            pendingCleanup = safe
            report = .init(
                tool: .prepareCleanup,
                findings: safe,
                facts: ["confirmation_required": "true", "source_tool": source.tool.rawValue]
            )
        case .finish:
            report = lastReport ?? .init(tool: .finish, findings: [], facts: [:])
        }

        if tool != .finish && tool != .listResults && tool != .prepareCleanup {
            lastReport = report
        }
        return report
    }

    func confirmCleanup() async -> MacAgentCleanupResult {
        guard !isCleaning else { return .init(cleanedCount: 0, cleanedBytes: 0, failedCount: 0) }
        let targets = pendingCleanup
        guard !targets.isEmpty else { return .init(cleanedCount: 0, cleanedBytes: 0, failedCount: 0) }
        isCleaning = true
        defer { isCleaning = false }
        let task = Task.detached(priority: .userInitiated) { await Self.cleanFindings(targets) }
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        pendingCleanup = targets.filter { result.failedPaths.contains($0.path) }
        return result
    }

    nonisolated static func cleanFindings(
        _ targets: [MacAgentFinding],
        allowed: (MacAgentFinding) -> Bool = { isSafeCleanupFinding($0) },
        moveToTrash: (URL) throws -> Void = { try DeletionLogService.shared.trashItem(at: $0, category: "MaintenanceAgent") },
        recordFailure: (RemovalFailure) -> Void = { DeletionLogService.shared.logFailure($0, category: "MaintenanceAgent") }
    ) async -> MacAgentCleanupResult {
        var count = 0
        var bytes: Int64 = 0
        var failed = Set<String>()
        var seen = Set<String>()
        for finding in targets where seen.insert(finding.path).inserted {
            let url = URL(fileURLWithPath: finding.path)
            do {
                guard !Task.isCancelled else { throw CancellationError() }
                guard allowed(finding) else {
                    throw NSError(domain: "CleanupSafety", code: 1, userInfo: [NSLocalizedDescriptionKey:
                        "The file changed, is protected, or is no longer eligible for cleanup."])
                }
                try moveToTrash(url)
                count += 1
                bytes += finding.size
            } catch {
                failed.insert(finding.path)
                recordFailure(RemovalFailure(path: url, error: error))
            }
        }
        return .init(cleanedCount: count, cleanedBytes: bytes, failedCount: failed.count, failedPaths: failed)
    }

    func cancelCleanup() {
        pendingCleanup = []
    }

    nonisolated private static func scanJunk(olderThanDays: Int) -> MacAgentToolReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [(URL, MacAgentFindingCategory)] = [
            (home.appendingPathComponent("Library/Caches", isDirectory: true), .userCache),
            (home.appendingPathComponent("Library/Logs", isDirectory: true), .userLog),
            (home.appendingPathComponent("Library/Application Support/CrashReporter", isDirectory: true), .crashReport),
            (URL(fileURLWithPath: "/Library/Caches", isDirectory: true), .systemCache),
            (URL(fileURLWithPath: "/Library/Logs", isDirectory: true), .systemLog)
        ]
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
        var findings: [MacAgentFinding] = []
        for (root, category) in roots {
            findings.append(contentsOf: enumerateFiles(at: root, category: category, limit: 20_000) { values in
                guard let modified = values.contentModificationDate else { return false }
                return modified < cutoff
            })
            if findings.count >= 20_000 { break }
        }
        return .init(tool: .scanJunk, findings: Array(findings.prefix(20_000)), facts: ["older_than_days": String(olderThanDays)])
    }

    nonisolated private static func scanLargeFiles(minimumSizeMB: Int) -> MacAgentToolReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
        let threshold = Int64(minimumSizeMB) * 1_048_576
        var findings: [MacAgentFinding] = []
        for root in roots {
            findings.append(contentsOf: enumerateFiles(at: root, category: .largeFile, limit: 10_000) { values in
                Int64(values.fileSize ?? 0) >= threshold
            })
        }
        findings.sort { $0.size > $1.size }
        return .init(tool: .scanLargeFiles, findings: Array(findings.prefix(10_000)), facts: ["minimum_size_mb": String(minimumSizeMB)])
    }

    nonisolated private static func scanDuplicates() -> MacAgentToolReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
        return duplicateReport(in: roots)
    }

    nonisolated static func duplicateReport(in roots: [URL], limit: Int = 50_000) -> MacAgentToolReport {
        var candidates: [MacAgentFinding] = []
        for root in roots {
            candidates.append(contentsOf: enumerateFiles(at: root, category: .duplicateFile, limit: limit) { values in
                (values.fileSize ?? 0) >= 1_024
            })
            if candidates.count >= limit { break }
        }

        let sameSizeGroups = Dictionary(grouping: candidates, by: \.size).values.filter { $0.count > 1 }
        var redundantFiles: [MacAgentFinding] = []
        var duplicateGroupCount = 0

        for sizeGroup in sameSizeGroups {
            var byDigest: [String: [MacAgentFinding]] = [:]
            for finding in sizeGroup {
                guard let digest = sha256(of: URL(fileURLWithPath: finding.path)) else { continue }
                byDigest[digest, default: []].append(finding)
            }
            for digestGroup in byDigest.values where digestGroup.count > 1 {
                duplicateGroupCount += 1
                let sorted = digestGroup.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                redundantFiles.append(contentsOf: sorted.dropFirst())
            }
        }

        redundantFiles.sort { $0.size > $1.size }
        return .init(
            tool: .scanDuplicates,
            findings: redundantFiles,
            facts: [
                "duplicate_groups": String(duplicateGroupCount),
                "hash_algorithm": "SHA-256",
                "files_examined": String(candidates.count)
            ]
        )
    }

    nonisolated private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

    nonisolated private static func inspectStorage() -> MacAgentToolReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return .init(tool: .inspectStorage, findings: [], facts: [
            "total_bytes": String(values?.volumeTotalCapacity ?? 0),
            "available_bytes": String(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        ])
    }

    nonisolated private static func inspectSystem() -> MacAgentToolReport {
        let process = ProcessInfo.processInfo
        let thermal: String
        switch process.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        return .init(tool: .inspectSystem, findings: [], facts: [
            "processor_count": String(process.processorCount),
            "active_processor_count": String(process.activeProcessorCount),
            "physical_memory_bytes": String(process.physicalMemory),
            "uptime_seconds": String(Int(process.systemUptime)),
            "thermal_state": thermal,
            "low_power_mode": process.isLowPowerModeEnabled ? "true" : "false"
        ])
    }

    nonisolated private static func inspectStartup() -> MacAgentToolReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true),
            URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true)
        ]
        let findings = roots.flatMap { enumerateFiles(at: $0, category: .startupItem, limit: 2_000) { _ in true } }
        return .init(tool: .inspectStartup, findings: findings, facts: [:])
    }

    nonisolated private static func enumerateFiles(
        at root: URL,
        category: MacAgentFindingCategory,
        limit: Int,
        include: (URLResourceValues) -> Bool
    ) -> [MacAgentFinding] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [MacAgentFinding] = []
        for case let url as URL in enumerator {
            if Task.isCancelled || results.count >= limit { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  include(values) else { continue }
            results.append(.init(
                path: url.standardizedFileURL.path,
                category: category,
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate
            ))
        }
        return results
    }

    nonisolated static func isSafeCleanupFinding(
        _ finding: MacAgentFinding,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(),
        permitted: (URL) -> Bool = { SafetyGuard.shared.isSafeToDelete($0) }
    ) -> Bool {
        guard [.userCache, .userLog, .crashReport, .systemCache, .systemLog].contains(finding.category) else { return false }
        let home = homeDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        let allowedRoots = ["\(home)/Library/Caches/", "\(home)/Library/Logs/",
                            "\(home)/Library/Application Support/CrashReporter/", "/Library/Caches/", "/Library/Logs/"]
        let url = URL(fileURLWithPath: finding.path).standardizedFileURL
        let canonical = url.resolvingSymlinksInPath()
        guard allowedRoots.contains(where: canonical.path.hasPrefix), url.path == canonical.path,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let modified = values.contentModificationDate, let scannedDate = finding.modifiedAt,
              modified == scannedDate, now.timeIntervalSince(modified) >= 86400,
              Int64(values.fileSize ?? -1) == finding.size, permitted(url) else { return false }
        return true
    }
}
