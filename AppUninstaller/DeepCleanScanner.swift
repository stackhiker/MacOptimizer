import SwiftUI
import Combine

// MARK: - Models

struct DeepCleanItem: Identifiable, @unchecked Sendable {
    let id = UUID()
    let url: URL
    /// Display accounting uses the path captured by the scan, never fresh I/O.
    let canonicalPath: String
    let name: String
    let size: Int64
    let category: DeepCleanCategory
    let installationResidue: InstallationResidue?
    var isSelected: Bool = true

    init(url: URL, name: String, size: Int64, category: DeepCleanCategory,
         isSelected: Bool? = nil, appIcon: NSImage? = nil, bundleId: String? = nil,
         installationResidue: InstallationResidue? = nil) {
        self.url = url
        self.canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        self.name = name
        self.size = size
        self.category = category
        self.installationResidue = installationResidue
        // Personal files and inferred leftovers require an explicit selection.
        self.isSelected = isSelected ?? (category != .largeFiles && category != .appResiduals && category != .installationResidues)
        self.appIcon = appIcon
        self.bundleId = bundleId
    }
    
    // New metadata for Apps
    var appIcon: NSImage? = nil
    var bundleId: String? = nil
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var installationReviewReason: String? {
        guard let installationResidue else { return nil }
        let loc = LocalizationManager.shared
        switch installationResidue.kind {
        case .appBackup: return loc.text(simplifiedChinese: "旧版本应用备份；请确认不再需要回退。", traditionalChinese: "舊版本應用程式備份；請確認不再需要還原。", english: "Old app backup; confirm you no longer need it for rollback.", japanese: "旧アプリのバックアップです。復元が不要か確認してください。", korean: "이전 앱 백업입니다. 복원이 필요 없는지 확인하세요.", russian: "Старая копия приложения. Убедитесь, что откат не нужен.")
        case .codexInstallStaging: return loc.text(simplifiedChinese: "已停用的安装暂存文件；请确认当前版本可正常使用。", traditionalChinese: "已停用的安裝暫存檔；請確認目前版本可正常使用。", english: "Inactive installation files; confirm the current version works.", japanese: "未使用のインストールファイルです。現在のバージョンの動作を確認してください。", korean: "사용하지 않는 설치 파일입니다. 현재 버전의 작동을 확인하세요.", russian: "Неактивные файлы установки. Проверьте работу текущей версии.")
        case .sparkleDownload: return loc.text(simplifiedChinese: "旧更新下载包；再次安装时可能需要重新下载。", traditionalChinese: "舊更新下載套件；再次安裝時可能需要重新下載。", english: "Old update download; reinstalling may require another download.", japanese: "古い更新パッケージです。再インストール時に再ダウンロードが必要な場合があります。", korean: "이전 업데이트 파일입니다. 재설치 시 다시 다운로드해야 할 수 있습니다.", russian: "Старый пакет обновления. Для переустановки может потребоваться загрузка.")
        case .verificationTemporary: return loc.text(simplifiedChinese: "安装验证留下的临时文件；请确认安装已完成。", traditionalChinese: "安裝驗證留下的暫存檔；請確認安裝已完成。", english: "Temporary installation verification files; confirm installation is complete.", japanese: "インストール確認用の一時ファイルです。インストール完了を確認してください。", korean: "설치 확인용 임시 파일입니다. 설치가 완료되었는지 확인하세요.", russian: "Временные файлы проверки установки. Убедитесь, что установка завершена.")
        case .projectBackup: return loc.text(simplifiedChinese: "优化大师的旧构建备份；请确认不再需要回退。", traditionalChinese: "優化大師的舊建置備份；請確認不再需要還原。", english: "Old Mac Optimizer build backup; confirm rollback is no longer needed.", japanese: "Mac Optimizer の旧ビルドのバックアップです。復元が不要か確認してください。", korean: "Mac Optimizer 이전 빌드 백업입니다. 복원이 필요 없는지 확인하세요.", russian: "Старая сборка Mac Optimizer. Убедитесь, что откат не нужен.")
        }
    }
}

// MARK: - App Info Helper Structure
struct InstalledAppInfo {
    let name: String
    let bundleId: String
    let url: URL
    let icon: NSImage
}

enum DeepCleanCategory: String, CaseIterable, Sendable {
    case largeFiles = "Large Files"
    case junkFiles = "System Junk"
    case systemLogs = "Log Files"
    case systemCaches = "Cache Files"
    case appResiduals = "App Residue"
    case installationResidues = "Installation Residue"
    
    var localizedName: String {
        let loc = LocalizationManager.shared
        switch self {
        case .largeFiles: return loc.text(simplifiedChinese: "大文件", traditionalChinese: "大型檔案", english: "Large Files", japanese: "大容量ファイル", korean: "대용량 파일", russian: "Большие файлы")
        case .junkFiles: return loc.text(simplifiedChinese: "系统垃圾", traditionalChinese: "系統垃圾", english: "System Junk", japanese: "システムジャンク", korean: "시스템 정크", russian: "Системный мусор")
        case .systemLogs: return loc.text(simplifiedChinese: "日志文件", traditionalChinese: "日誌檔案", english: "Log Files", japanese: "ログファイル", korean: "로그 파일", russian: "Файлы журналов")
        case .systemCaches: return loc.text(simplifiedChinese: "缓存文件", traditionalChinese: "快取檔案", english: "Cache Files", japanese: "キャッシュファイル", korean: "캐시 파일", russian: "Файлы кэша")
        case .appResiduals: return loc.text(simplifiedChinese: "应用残留", traditionalChinese: "應用程式殘留", english: "App Residue", japanese: "アプリの残存ファイル", korean: "앱 잔여 파일", russian: "Остатки приложений")
        case .installationResidues: return loc.text(simplifiedChinese: "安装残留与旧备份", traditionalChinese: "安裝殘留與舊備份", english: "Install Leftovers & Old Backups", japanese: "インストール残存と旧バックアップ", korean: "설치 잔여 파일 및 이전 백업", russian: "Остатки установки и старые копии")
        }
    }
    
    var icon: String {
        switch self {
        case .largeFiles: return "arrow.down.doc.fill"
        case .junkFiles: return "trash.fill"
        case .systemLogs: return "doc.text.fill"
        case .systemCaches: return "externaldrive.fill"
        case .appResiduals: return "exclamationmark.triangle.fill"
        case .installationResidues: return "shippingbox.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .largeFiles: return .purple
        case .junkFiles: return .red
        case .systemLogs: return .gray
        case .systemCaches: return .blue
        case .appResiduals: return .orange
        case .installationResidues: return .indigo
        }
    }
}

struct DeepCleanResult {
    let count: Int
    /// Logical size moved to Trash, not a promise of reclaimed disk blocks.
    let size: Int64
    let failures: [RemovalFailure]
    let wasStopped: Bool
    let diskSpaceChange: Int64?
}

private enum DeepCleanScanSession {
    @TaskLocal static var id: UUID?
}

private struct DeepCleanMergeEntry: Sendable {
    let index: Int
    let url: URL
    let path: String
    let size: Int64
    let isNew: Bool
    let isInstallationResidue: Bool
}

// MARK: - Scanner

class DeepCleanScanner: ObservableObject {
    @Published var items: [DeepCleanItem] = [] {
        didSet {
            selectedSummaryCache = nil
            itemsRevision &+= 1
        }
    }
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var scanProgress: Double = 0.0
    @Published var scanStatus: String = ""
    @Published var currentScanningUrl: String = ""
    @Published var completedCategories: Set<DeepCleanCategory> = []
    
    // 统计数据
    @Published var totalSize: Int64 = 0
    @Published var cleanedSize: Int64 = 0
    @Published var cleaningProgress: Double = 0.0
    @Published var currentCleaningItem: String = ""
    
    // 清理状态跟踪
    @Published var cleaningCurrentCategory: DeepCleanCategory? = nil
    @Published var cleanedCategories: Set<DeepCleanCategory> = []
    @Published var cleaningDescription: String = ""
    
    // 选中的大小
    var selectedSize: Int64 { selectedSummary.size }
    var selectedCount: Int { selectedSummary.count }

    private var selectedSummaryCache: (size: Int64, count: Int)?
    private var itemsRevision: UInt64 = 0
    private(set) var selectedSummaryBuildCount = 0

    private var selectedSummary: (size: Int64, count: Int) {
        if let selectedSummaryCache { return selectedSummaryCache }
        let selected = items.filter(\.isSelected)
        let roots = Set(CleanupFileSystem.uniqueRootPaths(selected.map(\.canonicalPath)))
        var seen = Set<String>()
        var summary: (size: Int64, count: Int) = (0, 0)
        for item in selected where roots.contains(item.canonicalPath) {
            guard seen.insert(item.canonicalPath).inserted else { continue }
            summary.size += item.size
            summary.count += 1
        }
        selectedSummaryCache = summary
        selectedSummaryBuildCount += 1
        return summary
    }
    
    // Progress smoothing
    private var currentTaskProgressRange: (start: Double, end: Double) = (0, 0)
    private var scannedItemsCount: Int = 0
    private let progressSmoothingFactor: Double = 1000.0 // Items to reach 50% of range
    
    private let fileManager = FileManager.default
    @MainActor private var scanTask: Task<Void, Never>?
    @MainActor private var activeScanID: UUID?
    @Published private(set) var isStoppingScan = false
    @Published private(set) var scanWasStopped = false
    @Published private(set) var lastFailures: [RemovalFailure] = []
    @Published private(set) var lastCleanupResult: DeepCleanResult?
    private let scanCategory: ((DeepCleanCategory) async -> [DeepCleanItem])?
    private let trashItem: (URL) async throws -> Void
    private let deletionAllowed: (URL, Bool) -> Bool
    private let recordFailure: (RemovalFailure) -> Void
    private let scanRootSelector: @Sendable ([String]) -> [String]
    private let scanInstallationResidues: () async -> [InstallationResidue]
    private let residueValidator: (InstallationResidue) async -> Bool

    init(scanCategory: ((DeepCleanCategory) async -> [DeepCleanItem])? = nil,
         trashItem: @escaping (URL) async throws -> Void = {
             try DeletionLogService.shared.trashItem(at: $0, category: "DeepClean")
         },
         deletionAllowed: @escaping (URL, Bool) -> Bool = {
             SafetyGuard.shared.isSafeToDelete($0, ignoreProtection: $1)
         },
         recordFailure: @escaping (RemovalFailure) -> Void = {
             DeletionLogService.shared.logFailure($0, category: "DeepClean")
         },
         scanRootSelector: @escaping @Sendable ([String]) -> [String] = {
             CleanupFileSystem.uniqueRootPaths($0)
         },
         scanInstallationResidues: (() async -> [InstallationResidue])? = nil,
         residueValidator: @escaping (InstallationResidue) async -> Bool = {
             await SafetyGuard.shared.isSafeToDeleteInstallationResidue($0)
         }) {
        self.scanCategory = scanCategory
        self.trashItem = trashItem
        self.deletionAllowed = deletionAllowed
        self.recordFailure = recordFailure
        self.scanRootSelector = scanRootSelector
        if let scanInstallationResidues {
            self.scanInstallationResidues = scanInstallationResidues
        } else if scanCategory != nil {
            self.scanInstallationResidues = { [] }
        } else {
            self.scanInstallationResidues = {
                await InstallationResidueScanner().scan(shouldCancel: { Task.isCancelled })
            }
        }
        self.residueValidator = residueValidator
    }
    
    // 系统保护 - 绝对不删
    private let protectedPaths: Set<String> = [
        "/System",
        "/bin",
        "/sbin",
        "/usr",
        "/var/root"
    ]
    
    // MARK: - API
    
    @Published var currentCategory: DeepCleanCategory = .largeFiles // Default, updates during scan
    
    // MARK: - API
    
    @MainActor
    func startScan() async {
        guard scanTask == nil, !isScanning, !isCleaning, !Task.isCancelled else { return }
        reset()
        let id = UUID()
        activeScanID = id
        isScanning = true
        scanStatus = LocalizationManager.shared.text("正在准备…", "Preparing…")
        let task = Task {
            await DeepCleanScanSession.$id.withValue(id) {
                await self.performScan(id: id)
            }
        }
        scanTask = task
        await withTaskCancellationHandler(operation: {
            await task.value
        }, onCancel: {
            task.cancel()
        })
        guard activeScanID == id else { return }
        scanWasStopped = isStoppingScan || task.isCancelled
        scanStatus = LocalizationManager.shared.text(
            scanWasStopped ? "扫描已停止" : "扫描完成",
            scanWasStopped ? "Scan stopped" : "Scan complete")
        if !scanWasStopped { scanProgress = 1 }
        currentScanningUrl = ""
        activeScanID = nil
        scanTask = nil
        isStoppingScan = false
        isScanning = false
    }

    private func performScan(id: UUID) async {
        let categories: [DeepCleanCategory] = [.junkFiles, .systemLogs, .systemCaches, .appResiduals, .largeFiles, .installationResidues]
        for (index, category) in categories.enumerated() {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard activeScanID == id else { return }
                currentCategory = category
                scanStatus = statusText(for: category)
                currentTaskProgressRange = (Double(index) / Double(categories.count), Double(index + 1) / Double(categories.count))
                scannedItemsCount = 0
                scanProgress = currentTaskProgressRange.start
            }
            let newItems: [DeepCleanItem]
            if category == .installationResidues {
                newItems = await scanInstallationResidues().map {
                    DeepCleanItem(url: $0.url, name: $0.name, size: $0.size,
                                  category: .installationResidues, isSelected: false, installationResidue: $0)
                }
            } else if let scanCategory {
                newItems = await scanCategory(category)
            } else {
                switch category {
                case .largeFiles: newItems = await scanLargeFiles()
                case .junkFiles: newItems = await scanJunk()
                case .systemLogs: newItems = await scanLogs()
                case .systemCaches: newItems = await scanCaches()
                case .appResiduals: newItems = await scanResiduals()
                case .installationResidues: newItems = [] // Handled above.
                }
            }
            guard !Task.isCancelled else { return }
            await mergeScanResults(newItems, category: category,
                                   progress: Double(index + 1) / Double(categories.count), scanID: id)
        }
    }

    private func mergeScanResults(_ newItems: [DeepCleanItem], category: DeepCleanCategory,
                                  progress: Double, scanID: UUID) async {
        while !Task.isCancelled {
            let current = await MainActor.run { () -> (items: [DeepCleanItem], revision: UInt64)? in
                guard activeScanID == scanID, !isStoppingScan else { return nil }
                return (items, itemsRevision)
            }
            guard let current else { return }
            let candidates = current.items + newItems
            let snapshot = candidates.enumerated().map {
                DeepCleanMergeEntry(index: $0.offset, url: $0.element.url,
                                    path: $0.element.canonicalPath, size: $0.element.size,
                                    isNew: $0.offset >= current.items.count,
                                    isInstallationResidue: $0.element.category == .installationResidues)
            }
            let selectRoots = scanRootSelector
            let worker = Task.detached(priority: .utility) { () -> (indices: [Int], size: Int64)? in
                guard !Task.isCancelled else { return nil }
                let visible = snapshot.filter {
                    ($0.isInstallationResidue || !InstallationResidueScanner.excludesGenericCleanup($0.url)) &&
                    (!$0.isNew || ScanResultIgnoreStore.shouldInclude($0.url))
                }
                let roots = Set(selectRoots(visible.map(\.path)))
                guard !Task.isCancelled else { return nil }
                var seen = Set<String>()
                let retained = visible.filter { roots.contains($0.path) && seen.insert($0.path).inserted }
                    .sorted { $0.size > $1.size }
                return (retained.map(\.index), retained.reduce(0) { $0 + $1.size })
            }
            let result = await withTaskCancellationHandler(operation: {
                await worker.value
            }, onCancel: {
                worker.cancel()
            })
            guard let result, !Task.isCancelled else { return }
            let finished = await MainActor.run {
                guard activeScanID == scanID, !isStoppingScan, !Task.isCancelled else { return true }
                // Preserve a selection or ignore change made while merging.
                guard itemsRevision == current.revision else { return false }
                items = result.indices.map { candidates[$0] }
                totalSize = result.size
                completedCategories.insert(category)
                scanProgress = progress
                return true
            }
            if finished { return }
        }
    }

    /// Keep one top-level path before displaying totals or performing a cleanup.
    static func uniqueItems(_ candidates: [DeepCleanItem]) -> [DeepCleanItem] {
        let roots = Set(CleanupFileSystem.uniqueRoots(candidates.map { $0.url.standardizedFileURL.resolvingSymlinksInPath() }).map {
            $0.standardizedFileURL.resolvingSymlinksInPath().path
        })
        var seen = Set<String>()
        return candidates.filter {
            let path = $0.url.standardizedFileURL.resolvingSymlinksInPath().path
            return roots.contains(path) && seen.insert(path).inserted
        }
    }

    private func statusText(for category: DeepCleanCategory) -> String {
        let loc = LocalizationManager.shared
        switch category {
        case .largeFiles: return loc.text(simplifiedChinese: "正在扫描大文件…", traditionalChinese: "正在掃描大型檔案…", english: "Scanning Large Files…", japanese: "大容量ファイルをスキャン中…", korean: "대용량 파일 스캔 중…", russian: "Сканирование больших файлов…")
        case .junkFiles: return loc.text(simplifiedChinese: "正在扫描系统垃圾…", traditionalChinese: "正在掃描系統垃圾…", english: "Scanning System Junk…", japanese: "システムジャンクをスキャン中…", korean: "시스템 정크 스캔 중…", russian: "Сканирование системного мусора…")
        case .systemLogs: return loc.text(simplifiedChinese: "正在扫描日志…", traditionalChinese: "正在掃描日誌…", english: "Scanning Logs…", japanese: "ログをスキャン中…", korean: "로그 스캔 중…", russian: "Сканирование журналов…")
        case .systemCaches: return loc.text(simplifiedChinese: "正在扫描缓存…", traditionalChinese: "正在掃描快取…", english: "Scanning Caches…", japanese: "キャッシュをスキャン中…", korean: "캐시 스캔 중…", russian: "Сканирование кэша…")
        case .appResiduals: return loc.text(simplifiedChinese: "正在扫描应用残留…", traditionalChinese: "正在掃描應用程式殘留…", english: "Scanning App Residue…", japanese: "アプリの残存ファイルをスキャン中…", korean: "앱 잔여 파일 스캔 중…", russian: "Сканирование остатков приложений…")
        case .installationResidues: return loc.text(simplifiedChinese: "正在检查安装残留与旧备份…", traditionalChinese: "正在檢查安裝殘留與舊備份…", english: "Checking Install Leftovers and Old Backups…", japanese: "インストール残存と旧バックアップを確認中…", korean: "설치 잔여 파일 및 이전 백업 확인 중…", russian: "Проверка остатков установки и старых копий…")
        }
    }
    
    // The producer may run on a scanning worker; publish only for its live session.
    private let progressLock = NSLock()
    private var lastUpdateTime = Date.distantPast

    func updateScanningUrl(_ url: String) {
        guard !Task.isCancelled, let id = DeepCleanScanSession.id else { return }
        let now = Date()
        progressLock.lock()
        let shouldPublish = now.timeIntervalSince(lastUpdateTime) >= 0.1
        if shouldPublish { lastUpdateTime = now }
        progressLock.unlock()
        guard shouldPublish else { return }
        Task { @MainActor in
            guard self.activeScanID == id, self.isScanning, !self.isStoppingScan else { return }
            self.currentScanningUrl = url
            self.scannedItemsCount += 1
            let progress = 1.0 - (1.0 / (1.0 + Double(self.scannedItemsCount) / self.progressSmoothingFactor))
            let (start, end) = self.currentTaskProgressRange
            self.scanProgress = max(self.scanProgress, start + (end - start) * progress)
        }
    }

    func sizeFor(category: DeepCleanCategory) -> Int64 {
        return items.filter { $0.category == category && $0.isSelected }.reduce(0) { $0 + $1.size }
    }

    /// Reuses the production orphan-detection rules for the Uninstaller's
    /// dedicated "Leftovers" category without starting an unrelated full-disk scan.
    func scanUninstallerResiduals() async -> [DeepCleanItem] {
        await scanResiduals()
    }
    
    @MainActor
    func stopScan() {
        guard let scanTask else { return }
        isStoppingScan = true
        scanStatus = LocalizationManager.shared.text("正在停止扫描…", "Stopping scan…")
        scanTask.cancel()
        // Ownership remains until the worker exits. Starting another scan or a
        // cleanup now would mix two operations against the same result list.
    }

    @MainActor
    func cleanSelected() async -> DeepCleanResult {
        guard !isScanning, scanTask == nil, !isCleaning else {
            return DeepCleanResult(count: 0, size: 0, failures: [], wasStopped: true, diskSpaceChange: nil)
        }
        let selected = Self.uniqueItems(items.filter(\.isSelected))
        isCleaning = true
        cleaningProgress = 0
        cleanedSize = 0
        lastFailures = []
        cleanedCategories = []
        let before = CleanupDiskSnapshot.capture()
        var completed = Set<String>()
        var failures: [RemovalFailure] = []
        var count = 0
        var logicalBytes: Int64 = 0
        defer {
            isCleaning = false
            currentCleaningItem = ""
            cleaningCurrentCategory = nil
        }
        for (index, item) in selected.enumerated() {
            guard !Task.isCancelled else { break }
            currentCleaningItem = item.name
            cleaningCurrentCategory = item.category
            cleaningDescription = LocalizationManager.shared.text("正在移入废纸篓…", "Moving to Trash…")
            do {
                guard await canRemove(item) else {
                    throw NSError(domain: "MacOptimizer.CleanupSafety", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: LocalizationManager.shared.text(
                                    "此项目受保护或正在使用，已保留。", "This item is protected or in use and was kept.")])
                }
                guard !Task.isCancelled else { break }
                try await trashItem(item.url)
                completed.insert(item.url.standardizedFileURL.resolvingSymlinksInPath().path)
                count += 1
                logicalBytes += item.size
                cleanedSize = logicalBytes
            } catch {
                let failure = RemovalFailure(path: item.url, error: error)
                failures.append(failure)
                recordFailure(failure)
            }
            cleanedCategories.insert(item.category)
            cleaningProgress = Double(index + 1) / Double(max(1, selected.count))
            await Task.yield()
        }
        items.removeAll { item in
            let path = item.url.standardizedFileURL.resolvingSymlinksInPath().path
            return completed.contains(path) || completed.contains { path.hasPrefix($0 + "/") }
        }
        totalSize = Self.uniqueItems(items).reduce(0) { $0 + $1.size }
        lastFailures = failures
        let change = before.flatMap { previous in CleanupDiskSnapshot.capture()?.change(since: previous) }
        let result = DeepCleanResult(count: count, size: logicalBytes, failures: failures,
                                     wasStopped: Task.isCancelled, diskSpaceChange: change)
        lastCleanupResult = result
        scanStatus = LocalizationManager.shared.text(
            failures.isEmpty ? "已移入废纸篓" : "部分项目未能移入废纸篓",
            failures.isEmpty ? "Moved to Trash" : "Some items could not be moved to Trash")
        return result
    }

    @MainActor
    private func canRemove(_ item: DeepCleanItem) async -> Bool {
        if item.category == .installationResidues {
            guard let candidate = item.installationResidue,
                  candidate.url == item.url,
                  !Task.isCancelled else { return false }
            return await residueValidator(candidate)
        }
        guard !InstallationResidueScanner.excludesGenericCleanup(item.url) else { return false }
        return deletionAllowed(item.url, item.category == .largeFiles)
    }

    @MainActor
    func reset() {
        guard !isScanning, scanTask == nil, !isCleaning else { stopScan(); return }
        items = []
        totalSize = 0
        cleanedSize = 0
        scanProgress = 0
        scanStatus = ""
        currentScanningUrl = ""
        completedCategories = []
        cleaningCurrentCategory = nil
        cleanedCategories = []
        cleaningDescription = ""
        scanWasStopped = false
        lastFailures = []
        lastCleanupResult = nil
    }

    // MARK: - Helper Methods
    
    private func updateStatus(_ status: String, category: DeepCleanCategory? = nil) async {
        await MainActor.run {
            self.scanStatus = status
        }
    }
    
    // MARK: - Scanning Implementations
    
    private func scanLargeFiles() async -> [DeepCleanItem] {
        // Scan User's Home Directory (~/) recursively
        let home = fileManager.homeDirectoryForCurrentUser
        let scanRoots = [home]
        
        // Exclude specific system/sensitive/app directories to prevent damage
        let config = ScanConfiguration(
            minFileSize: 50 * 1024 * 1024, // 50MB
            skipHiddenFiles: true,
            excludedPaths: [
                "Library",          // Contains App Data/Databases - Unsafe to delete single files
                "Applications",     // Apps themselves
                ".Trash",           // Already in Trash
                ".vol", ".Db",      // System mounts
                "Music/Music Library", // Protect Music Library DB
                "Pictures/Photos Library.photoslibrary" // Protect Photos DB
            ]
        )
        
        let results = await scanDirectoryConcurrently(directories: scanRoots, configuration: config) { url, values -> DeepCleanItem? in
            // SAFETY: Skip .app bundles and application-related files
            self.updateScanningUrl(url.path) // Trigger progress update
            
            if url.path.contains(".app") || 
               url.path.contains("/Applications/") ||
               url.path.contains("/Library/") { // Double check for Library in path
                return nil
            }
            
            return DeepCleanItem(
                url: url,
                name: url.lastPathComponent,
                size: Int64(values.fileSize ?? 0),
                category: .largeFiles
            )
        }
        
        return results
    }
    
    private func scanLogs() async -> [DeepCleanItem] {
        var logPaths = [String]()
        
        // 1. Standard Log Paths
        logPaths.append(contentsOf: [
            "~/Library/Logs",
            "~/Library/Application Support/CrashReporter",
            "~/Library/Logs/DiagnosticReports"
        ])
        
        // 2. Expand tilde
        let expandedPaths = logPaths.map { NSString(string: $0).expandingTildeInPath }
        
        let config = ScanConfiguration(
            minFileSize: 0,
            skipHiddenFiles: false
        )
        
        return await scanDirectoryConcurrently(directories: expandedPaths.map { URL(fileURLWithPath: $0) }, configuration: config) { url, values in
            self.updateScanningUrl(url.path)
            
            // Filter logic
            let isLog = url.pathExtension == "log" || 
                       url.pathExtension == "crash" ||
                       url.path.contains("/Logs/") || 
                       url.path.contains("/CrashReporter/")
            
            if isLog {
                return DeepCleanItem(
                    url: url,
                    name: url.lastPathComponent,
                    size: Int64(values.fileSize ?? 0),
                    category: .systemLogs
                )
            }
            return nil
        }
    }
    
    // MARK: - Dynamic App Scanning Helpers
    
    private func getInstalledApps() -> [InstalledAppInfo] {
        var apps: [InstalledAppInfo] = []
        let appDirs = [
            "/Applications",
            "/System/Applications",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        
        for dir in appDirs {
            if Task.isCancelled { break }
            guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents {
                if Task.isCancelled { break }
                if item.hasSuffix(".app") {
                    let appUrl = URL(fileURLWithPath: dir).appendingPathComponent(item)
                    // Get Bundle ID
                    if let bundle = Bundle(url: appUrl),
                       let bundleId = bundle.bundleIdentifier {
                        let icon = NSWorkspace.shared.icon(forFile: appUrl.path)
                        let name = (item as NSString).deletingPathExtension
                        apps.append(InstalledAppInfo(name: name, bundleId: bundleId, url: appUrl, icon: icon))
                    }
                }
            }
        }
        return apps
    }
    
    private func scanCaches() async -> [DeepCleanItem] {
        var items: [DeepCleanItem] = []
        
        // 1. Dynamic App Scanning
        let apps = getInstalledApps()
        let home = fileManager.homeDirectoryForCurrentUser
        
        for app in apps {
            guard !Task.isCancelled else { return items }
            let cacheUrl = home.appendingPathComponent("Library/Caches").appendingPathComponent(app.bundleId)
            guard fileManager.fileExists(atPath: cacheUrl.path),
                  SafetyGuard.shared.isSafeToDelete(cacheUrl) else { continue }
            updateScanningUrl(cacheUrl.path)
            let size = await calculateSizeAsync(at: cacheUrl)
            if size > 1024 * 1024 {
                items.append(DeepCleanItem(url: cacheUrl, name: localizedCacheName(for: app.name),
                                           size: size, category: .systemCaches,
                                           appIcon: app.icon, bundleId: app.bundleId))
            }
        }

        // 2. Scan Log Paths (using predicted Bundle IDs)
         // (This could be integrated here or in scanLogs, but let's stick to Caches for now as requested)
         
        // 3. Scan Generic Caches (browsers etc. matching specifically if not found by bundle ID)
        // Note: Chrome/Safari/etc usually have specific bundle IDs so getInstalledApps should catch them.
        // We can keep the manual list as a fallback or removal it?
        // Let's keep a small manual list for non-standard apps that might not be in /Applications or have weird cache paths (like Chrome's "Default/Cache")
        
        // Browsers specific paths not covered by Bundle ID Caches standard
        let manualItems = await scanManualCaches()
        items.append(contentsOf: manualItems)
        
        // Deduplicate
        return Self.uniqueItems(items)
    }
    
    private func scanManualCaches() async -> [DeepCleanItem] {
         var cachePaths = Set<String>()
        
        // Specific complex paths not just ~/Library/Caches/BundleID
        cachePaths.insert("~/Library/Caches/Google/Chrome") // Sometimes this is a container
        cachePaths.insert("~/Library/Application Support/Google/Chrome/Default/Cache")
        cachePaths.insert("~/Library/Caches/com.apple.Safari") // Safari uses standard ID but complex structure sometimes
        cachePaths.insert("~/Library/Caches/Firefox")
        
         // 3. Expand all paths
        let validPaths = cachePaths
            .map { NSString(string: $0).expandingTildeInPath }
            .map { URL(fileURLWithPath: $0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
            
        var items: [DeepCleanItem] = []
        for dir in validPaths {
            if Task.isCancelled { break }
            guard SafetyGuard.shared.isSafeToDelete(dir) else { continue }
             let size = await calculateSizeAsync(at: dir)
             if size > 1024 {
                var displayName = dir.lastPathComponent
                if dir.path.contains("Chrome") { displayName = localizedCacheName(for: "Chrome") }
                else if dir.path.contains("Firefox") { displayName = localizedCacheName(for: "Firefox") }
                
                 items.append(DeepCleanItem(
                    url: dir,
                    name: displayName,
                    size: size,
                    category: .systemCaches
                ))
             }
        }
        return items
    }
    
    private func scanResiduals() async -> [DeepCleanItem] {
        print("[DeepClean] 🔍 开始扫描应用残留...")
        
        let home = fileManager.homeDirectoryForCurrentUser
        var items: [DeepCleanItem] = []
        
        // 1. 获取所有已安装应用的信息
        let installedApps = await getInstalledAppParams()
        print("[DeepClean] 📱 找到 \(installedApps.count) 个已安装应用")
        
        // 2. 扫描 Application Support (应用数据)
        let appSupport = home.appendingPathComponent("Library/Application Support")
        if fileManager.fileExists(atPath: appSupport.path) {
            updateScanningUrl(appSupport.path)
            if let contents = try? fileManager.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for folder in contents {
                    if Task.isCancelled { break }
                    // Update UI occasionally
                    if Int.random(in: 0...10) == 0 { await MainActor.run { self.updateScanningUrl(folder.path) } }
                    
                    let folderName = folder.lastPathComponent
                    
                    // ⚠️ 关键：使用 isOrphanedFolder 判断是否为残留
                    if isOrphanedFolder(name: folderName, installedApps: installedApps) {
                        // ⚠️ 再次使用 SafetyGuard 验证
                        if SafetyGuard.shared.isSafeToDelete(folder) {
                            let size = await calculateSizeAsync(at: folder)
                            if size > 100_000 { // 只添加大于100KB的残留
                                items.append(DeepCleanItem(
                                    url: folder,
                                    name: folderName,
                                    size: size,
                                    category: .appResiduals
                                ))
                                print("[DeepClean] 🗑️ 发现残留: \(folderName)")
                            }
                        }
                    }
                }
            }
        }
        
        // 3. 扫描 Preferences (偏好设置)
        // ⚠️ 注意：Preferences 包含大量系统服务配置，需要极其谨慎
        // 为了安全，暂时禁用 Preferences 扫描，避免误删系统配置
        // let prefs = home.appendingPathComponent("Library/Preferences")
        // print("[DeepClean] ⚠️ Preferences 扫描已禁用，以防误删系统配置")
        
        // 如果未来要启用，需要更严格的白名单
        /*
        if fileManager.fileExists(atPath: prefs.path) {
            updateScanningUrl(prefs.path)
            if let contents = try? fileManager.contentsOfDirectory(at: prefs, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for file in contents {
                    guard file.pathExtension == "plist" else { continue }
                    
                    let bundleId = file.deletingPathExtension().lastPathComponent
                    
                    // 额外的安全检查
                    if isOrphanedFile(bundleId: bundleId, installedApps: installedApps) {
                        if SafetyGuard.shared.isSafeToDelete(file) {
                            // 只添加确定是第三方应用的 plist
                            if bundleId.contains(".") && 
                               !bundleId.hasPrefix("com.apple.") &&
                               !bundleId.hasPrefix("apple") {
                                if let attrs = try? fileManager.attributesOfItem(atPath: file.path),
                                   let size = attrs[.size] as? Int64, size > 100_000 { // 只添加 >100KB 的
                                    items.append(DeepCleanItem(
                                        url: file,
                                        name: file.lastPathComponent,
                                        size: size,
                                        category: .appResiduals
                                    ))
                                }
                            }
                        }
                    }
                }
            }
        }
        */
        
        // 4. 扫描 Containers (沙盒容器)
        let containers = home.appendingPathComponent("Library/Containers")
        if fileManager.fileExists(atPath: containers.path) {
            updateScanningUrl(containers.path)
            if let contents = try? fileManager.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for folder in contents {
                    if Task.isCancelled { break }
                    // Update UI occasionally
                    if Int.random(in: 0...10) == 0 { await MainActor.run { self.updateScanningUrl(folder.path) } }
                    
                    let bundleId = folder.lastPathComponent
                    
                    if isOrphanedFile(bundleId: bundleId, installedApps: installedApps) {
                        if SafetyGuard.shared.isSafeToDelete(folder) {
                            let size = await calculateSizeAsync(at: folder)
                            if size > 100_000 { // 只添加大于100KB的残留
                                items.append(DeepCleanItem(
                                    url: folder,
                                    name: bundleId,
                                    size: size,
                                    category: .appResiduals
                                ))
                            }
                        }
                    }
                }
            }
        }
        
        print("[DeepClean] ✅ 扫描完成，找到 \(items.count) 个应用残留")
        return items
    }
    
    // MARK: - 残留检测辅助方法
    
    /// 判断文件/文件夹名称是否为已卸载应用的残留
    private func isOrphanedFolder(name: String, installedApps: Set<String>) -> Bool {
        let lowerName = name.lowercased()
        
        // 1. 跳过系统目录和Apple服务
        let systemDirs = [
            // 核心系统目录
            "cloudkit", "geoservices", "familycircle", "knowledge", "metadata",
            "tmp", "t", "caches", "cache", "logs", "preferences", "temp",
            "cookies", "webkit", "httpstorages", "containers", "group containers",
            "databases", "keychains", "accounts", "mail", "calendars", "contacts",
            
            // Apple 应用和服务
            "safari", "finder", "dock", "spotlight", "siri",
            "passkit", "wallet",  // ⚠️ 钱包和密码服务
            "appstore", "facetime", "messages", "photos", "music", "tv",
            "icloud", "cloudphotosd", "cloudpaird",
            
            // 系统守护进程和代理
            "accountsd", "appleaccount", "identityservicesd",
            "itunesstored", "commerce", "storekit",
            "softwareupdate", "diagnostics"
        ]
        if systemDirs.contains(lowerName) { return false }
        
        // 2. 跳过以 . 开头的隐藏目录
        if name.hasPrefix(".") { return false }
        
        // 3. 跳过 Apple 系统目录
        if lowerName.hasPrefix("com.apple.") { return false }
        if lowerName.hasPrefix("apple") { return false }
        
        // 4. 检查是否匹配已安装应用
        // 精确匹配
        if installedApps.contains(lowerName) { return false }
        
        // 模糊匹配：检查是否包含已安装应用的名称
        for appId in installedApps {
            // 双向匹配
            if lowerName.contains(appId) || appId.contains(lowerName) {
                // 额外检查：避免误匹配过短的字符串
                if min(lowerName.count, appId.count) >= 5 {
                    return false
                }
            }
        }
        
        // 5. 检查 Bundle ID 格式的组件
        if lowerName.contains(".") {
            let components = lowerName.components(separatedBy: ".")
            for component in components where component.count >= 4 {
                for appId in installedApps {
                    if appId.contains(component) {
                        return false
                    }
                }
            }
        }
        
        // 通过所有检查，确认是残留
        return true
    }
    
    /// 判断 Bundle ID 是否为已卸载应用的残留
    private func isOrphanedFile(bundleId: String, installedApps: Set<String>) -> Bool {
        let lowerBundleId = bundleId.lowercased()
        
        // 1. 跳过以 . 开头的系统文件（如 .GlobalPreferences.plist）
        if bundleId.hasPrefix(".") { return false }
        
        // 2. 跳过所有 Apple 系统服务
        if lowerBundleId.hasPrefix("com.apple.") { return false }
        if lowerBundleId.hasPrefix("apple") { return false }
        
        // 3. 🛡️ 扩展的系统服务白名单（关键系统组件）
        let systemBundleIds = [
            // 核心系统服务
            "loginwindow", "finder", "dock", "systemuiserver", "controlcenter",
            "notificationcenter", "launchservicesd", "cfprefsd",
            
            // 系统守护进程
            "contextstoreagent", "contextstore",  // 上下文存储
            "pbs", "pasteboard",                   // 剪贴板服务
            "familycircled", "familycircle",       // 家庭共享
            "sharedfilelistd", "sharedfilelist",   // 共享文件列表
            "diagnostics_agent", "diagnostics",    // 系统诊断
            
            // Apple 账户和认证
            "passkit", "wallet", "passd",          // 钱包和密码服务 ⚠️ 重要
            "accountsd", "accounts",               // 账户管理
            "identityservicesd", "appleaccount",   // 身份验证
            
            // iCloud 和同步服务
            "cloudd", "icloud", "bird", "syncdefaultsd",
            "cloudphotosd", "cloudpaird", "cloudkitd",
            
            // App Store 和下载
            "itunesstored", "commerce", "storekit", "appstoreupdates",
            "softwareupdate", "softwareupdate_notify_agent",
            
            // 媒体和多媒体服务
            "mediaremoted", "coremedia", "avfoundation",
            "applemediaservices", "applemedialibrary",
            
            // 网络和安全
            "networkd", "securityd", "trustd", "keybagd",
            
            // 其他关键服务
            "coreduetd", "dasd", "rapportd", "askpermissiond"
        ]
        if systemBundleIds.contains(lowerBundleId) { return false }
        
        // 4. 精确匹配 Bundle ID
        if installedApps.contains(bundleId) || installedApps.contains(lowerBundleId) {
            return false
        }
        
        // 5. 模糊匹配：检查 Bundle ID 的各个组件
        let components = bundleId.components(separatedBy: ".")
        for component in components where component.count > 3 {
            for appId in installedApps {
                if appId.contains(component) || component.contains(appId) {
                    return false
                }
            }
        }
        
        // 通过所有检查，确认是残留
        return true
    }
    
    private func scanJunk() async -> [DeepCleanItem] {
        // Trash, Downloads (Older than X?), Xcode DerivedData
        let home = fileManager.homeDirectoryForCurrentUser
        var items: [DeepCleanItem] = []

        // Trash is handled by the dedicated Trash module, never as a file here.
        // 2. Xcode DerivedData
        let developer = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if fileManager.fileExists(atPath: developer.path) {
            updateScanningUrl(developer.path)
            let size = await calculateSizeAsync(at: developer)
             if size > 0 {
                items.append(DeepCleanItem(
                    url: developer,
                    name: "Xcode DerivedData",
                    size: size,
                    category: .junkFiles
                ))
            }
        }
        
        // Device backups are user data, not automatically selected junk.
        // 4. Mail Downloads
        let mailDownloads = home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")
        if fileManager.fileExists(atPath: mailDownloads.path) {
            updateScanningUrl(mailDownloads.path)
            let size = await calculateSizeAsync(at: mailDownloads)
            if size > 0 {
                items.append(DeepCleanItem(
                    url: mailDownloads,
                    name: LocalizationManager.shared.text(simplifiedChinese: "邮件附件", traditionalChinese: "郵件附件", english: "Mail Attachments", japanese: "メール添付ファイル", korean: "메일 첨부 파일", russian: "Почтовые вложения"),
                    size: size,
                    category: .junkFiles,
                    isSelected: false
                ))
            }
        }
        
        // 5. 应用缓存 (App Caches) - 扫描 ~/Library/Caches 中的应用缓存
        // ⚠️ 注意：Caches 目录包含大量系统和应用缓存
        // 为了安全，只扫描明确知道是第三方应用的缓存
        let cachesDir = home.appendingPathComponent("Library/Caches")
        if fileManager.fileExists(atPath: cachesDir.path) {
            updateScanningUrl(cachesDir.path)
            if let cacheContents = try? fileManager.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for cacheFolder in cacheContents {
                    if Task.isCancelled { break }
                    // Update UI occasionally
                    if Int.random(in: 0...5) == 0 { await MainActor.run { self.updateScanningUrl(cacheFolder.path) } }
                    
                    let folderName = cacheFolder.lastPathComponent.lowercased()
                    
                    // 🛡️ 第一层：明确跳过所有 Apple 系统缓存
                    if folderName.hasPrefix("com.apple.") {
                        continue  // 绝不扫描 Apple 系统缓存
                    }
                    
                    // 🛡️ 第二层：跳过当前正在运行的应用（我们自己的应用）
                    if folderName == "com.tool.appuninstaller" {
                        continue  // 不清理自己的缓存
                    }
                    
                    // 🛡️ 第三层：跳过已知的Apple系统服务缓存
                    let appleSystemServices = [
                        "passkit",  // Apple Wallet/密码服务
                        "cloudkit", "clouddocs", "cloudphotosd",
                        "familycircle", "familycircled",
                        "sqlite", "metadata", "applemedialibrary",
                        "applemediaservices", "itunesstored",
                        "commerce", "storekit", "appleaccount",
                        "accountsd", "identityservicesd",
                        "com.crashlytics", "diagnostics",
                        "appstoreupdates", "softwareupdate"
                    ]
                    if appleSystemServices.contains(folderName) {
                        continue  // 跳过Apple系统服务
                    }
                    
                    // 🛡️ 第四层：跳过所有正在运行的应用的缓存
                    let runningBundleIds = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() }
                    if runningBundleIds.contains(folderName) {
                        continue  // 不清理正在运行的应用的缓存
                    }
                    
                    // 🛡️ 第五层：SafetyGuard 最终检查
                    if SafetyGuard.shared.isSafeToDelete(cacheFolder) {
                        let size = await calculateSizeAsync(at: cacheFolder)
                        if size > 100_000 { // 只添加大于100KB的缓存
                            items.append(DeepCleanItem(
                                url: cacheFolder,
                                name: cacheFolder.lastPathComponent,
                                size: size,
                                category: .junkFiles
                            ))
                        }
                    }
                }
            }
        }
        
        // 6. 浏览器缓存 (Browser Caches)
        let browserCaches: [(name: String, path: String)] = [
            ("Safari", "Library/Caches/com.apple.Safari"),
            ("Chrome", "Library/Caches/Google/Chrome"),
            ("Firefox", "Library/Caches/Firefox"),
            ("Edge", "Library/Caches/com.microsoft.Edge")
        ]
        
        for (name, relativePath) in browserCaches {
            if Task.isCancelled { break }
            let cachePath = home.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: cachePath.path), SafetyGuard.shared.isSafeToDelete(cachePath) {
                updateScanningUrl(cachePath.path)
                let size = await calculateSizeAsync(at: cachePath)
                if size > 0 {
                    items.append(DeepCleanItem(
                        url: cachePath,
                        name: localizedCacheName(for: name),
                        size: size,
                        category: .junkFiles
                    ))
                }
            }
        }
        
        return items
    }

    private func localizedCacheName(for applicationName: String) -> String {
        LocalizationManager.shared.text(
            simplifiedChinese: "\(applicationName) 缓存",
            traditionalChinese: "\(applicationName) 快取",
            english: "\(applicationName) Cache",
            japanese: "\(applicationName) キャッシュ",
            korean: "\(applicationName) 캐시",
            russian: "Кэш \(applicationName)"
        )
    }
    
    // MARK: - App Helpers
    
    /// 获取已安装应用的标识符集合 (Bundle ID + Name) - 改进版
    private func getInstalledAppParams() async -> Set<String> {
        var params = Set<String>()
        
        // 1. 扫描标准应用目录
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        
        for dir in appDirs {
            if Task.isCancelled { break }
            guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            
            for item in contents {
                if Task.isCancelled { break }
                if item.hasSuffix(".app") {
                    // 添加应用名称 (去除后缀)
                    let name = (item as NSString).deletingPathExtension
                    params.insert(name.lowercased())
                    
                    // 读取 Info.plist 获取 Bundle ID
                    let appPath = (dir as NSString).appendingPathComponent(item)
                    let plistPath = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
                    
                    if let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
                       let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
                       let bundleId = plist["CFBundleIdentifier"] as? String {
                        params.insert(bundleId.lowercased())
                        
                        // 提取 Bundle ID 各组件
                        for component in bundleId.components(separatedBy: ".") where component.count > 3 {
                            params.insert(component.lowercased())
                        }
                    }
                }
            }
        }
        
        // 2. 添加 Homebrew Cask 应用
        let homebrewPaths = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
        for caskPath in homebrewPaths {
            if Task.isCancelled { break }
            if let casks = try? fileManager.contentsOfDirectory(atPath: caskPath) {
                for cask in casks {
                    if Task.isCancelled { break }
                    params.insert(cask.lowercased())
                }
            }
        }
        
        // 3. 添加正在运行的应用（最重要的安全检查）
        for app in NSWorkspace.shared.runningApplications {
            if Task.isCancelled { break }
            if let bundleId = app.bundleIdentifier {
                params.insert(bundleId.lowercased())
            }
            if let name = app.localizedName {
                params.insert(name.lowercased())
            }
        }
        
        // 4. 扩展的系统安全名单
        let systemSafelist = [
            // Apple 系统服务
            "com.apple", "cloudkit", "safari", "mail", "messages", "photos",
            "finder", "dock", "spotlight", "siri", "xcode", "instruments",
            "passkit", "wallet", "appstore", "facetime", "imessage",
            "familycircle", "familysharing", "icloud", "appleaccount",
            "findmy", "fmip", "healthkit", "homekit", "newsstand",
            "itunesstored", "commerce", "storekit", "applemediaservices",
            // 第三方常用应用
            "google", "chrome", "microsoft", "firefox", "adobe", "dropbox",
            "slack", "discord", "zoom", "telegram", "wechat", "qq", "tencent",
            "jetbrains", "vscode", "homebrew", "npm", "python", "ruby", "java",
            "todesk", "teamviewer", "anydesk"  // 远程桌面工具
        ]
        for safe in systemSafelist {
            params.insert(safe)
        }
        
        return params
    }
    
    private func isAppInstalled(_ name: String, params: Set<String>) -> Bool {
        let lowerName = name.lowercased()
        
        // 1. 直接匹配
        if params.contains(lowerName) { return true }
        
        // 2. 检查是否为系统保留
        if lowerName.starts(with: "com.apple.") { return true }
        if lowerName.starts(with: "apple") { return true }
        
        // 3. 模糊匹配：检查是否包含已安装应用名称
        for param in params {
            // 双向包含检查
            if lowerName.contains(param) || param.contains(lowerName) {
                return true
            }
        }
        
        // 4. 框架和插件保护
        let safePatterns = ["framework", "plugin", "extension", "helper", "service", "daemon", "agent"]
        for pattern in safePatterns {
            if lowerName.contains(pattern) { return true }
        }
        
        return false
    }

    
    // Toggle Logic
    func toggleSelection(for item: DeepCleanItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isSelected.toggle()
        }
        objectWillChange.send()
    }
    
    func toggleCategorySelection(_ category: DeepCleanCategory, to newState: Bool) {
        let categoryItems = items.filter { $0.category == category }
        for item in categoryItems {
            if let idx = items.firstIndex(where: { $0.id == item.id }) {
                items[idx].isSelected = newState
            }
        }
        objectWillChange.send()
    }
    
    func selectItems(in category: DeepCleanCategory) {
        for i in items.indices where items[i].category == category {
            items[i].isSelected = true
        }
    }
    
    func deselectItems(in category: DeepCleanCategory) {
        for i in items.indices where items[i].category == category {
            items[i].isSelected = false
        }
    }
    
    /// 删除单个项目
    @MainActor
    func deleteSingleItem(_ item: DeepCleanItem) async -> Bool {
        guard !isScanning, !isCleaning, scanTask == nil else { return false }
        isCleaning = true
        defer { isCleaning = false }
        do {
            guard await canRemove(item) else {
                throw NSError(domain: "MacOptimizer.CleanupSafety", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: LocalizationManager.shared.text(
                                "此项目受保护或正在使用，已保留。", "This item is protected or in use and was kept.")])
            }
            guard !Task.isCancelled else { return false }
            try await trashItem(item.url)
            items.removeAll { CleanupFileSystem.contains($0.url, in: item.url) }
            totalSize = Self.uniqueItems(items).reduce(0) { $0 + $1.size }
            return true
        } catch {
            let failure = RemovalFailure(path: item.url, error: error)
            lastFailures = [failure]
            recordFailure(failure)
            return false
        }
    }
}
