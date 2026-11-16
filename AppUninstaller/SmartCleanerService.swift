import Foundation
import AppKit
import SwiftUI
import CryptoKit
import Vision

// MARK: - 主分类（用于三栏布局）
enum MainCategory: String, CaseIterable, Identifiable {
    case systemJunk = "系统垃圾"
    case duplicates = "重复文件"
    case similarPhotos = "相似照片"
    case largeFiles = "大文件"
    case virus = "病毒威胁"
    case startupItems = "启动项"
    case performanceApps = "性能优化"
    case appUpdates = "应用更新"
    
    var id: String { rawValue }
    
    var englishName: String {
        switch self {
        case .systemJunk: return "System Junk"
        case .duplicates: return "Duplicates"
        case .similarPhotos: return "Similar Photos"
        case .largeFiles: return "Large Files"
        case .virus: return "Suspicious Items"
        case .startupItems: return "Startup Items"
        case .performanceApps: return "Performance"
        case .appUpdates: return "App Updates"
        }
    }

    func localizedName(for language: AppLanguage) -> String {
        if self == .virus {
            switch language {
            case .chinese: return "可疑项检查"
            case .traditionalChinese: return "可疑項目檢查"
            case .english: return "Suspicious Items"
            case .japanese: return "不審な項目"
            case .korean: return "의심 항목"
            case .russian: return "Подозрительные объекты"
            }
        }
        switch language {
        case .chinese:
            return rawValue
        case .traditionalChinese:
            switch self {
            case .systemJunk: return "系統垃圾"
            case .duplicates: return "重複檔案"
            case .similarPhotos: return "相似照片"
            case .largeFiles: return "大型檔案"
            case .virus: return "病毒威脅"
            case .startupItems: return "啟動項目"
            case .performanceApps: return "效能最佳化"
            case .appUpdates: return "應用程式更新"
            }
        case .english:
            return englishName
        case .japanese:
            switch self {
            case .systemJunk: return "システムジャンク"
            case .duplicates: return "重複ファイル"
            case .similarPhotos: return "類似写真"
            case .largeFiles: return "大容量ファイル"
            case .virus: return "ウイルスの脅威"
            case .startupItems: return "起動項目"
            case .performanceApps: return "パフォーマンス"
            case .appUpdates: return "アプリのアップデート"
            }
        case .korean:
            switch self {
            case .systemJunk: return "시스템 정크"
            case .duplicates: return "중복 파일"
            case .similarPhotos: return "유사한 사진"
            case .largeFiles: return "대용량 파일"
            case .virus: return "바이러스 위협"
            case .startupItems: return "시작 항목"
            case .performanceApps: return "성능 최적화"
            case .appUpdates: return "앱 업데이트"
            }
        case .russian:
            switch self {
            case .systemJunk: return "Системный мусор"
            case .duplicates: return "Дубликаты"
            case .similarPhotos: return "Похожие фотографии"
            case .largeFiles: return "Большие файлы"
            case .virus: return "Вирусные угрозы"
            case .startupItems: return "Объекты автозапуска"
            case .performanceApps: return "Производительность"
            case .appUpdates: return "Обновления приложений"
            }
        }
    }
    
    var icon: String {
        switch self {
        case .systemJunk: return "trash.fill"
        case .duplicates: return "doc.on.doc"
        case .similarPhotos: return "photo.on.rectangle"
        case .largeFiles: return "doc.fill"
        case .virus: return "shield.lefthalf.filled"
        case .startupItems: return "power.circle"
        case .performanceApps: return "bolt.fill"
        case .appUpdates: return "arrow.clockwise.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .systemJunk: return .pink
        case .duplicates: return .blue
        case .similarPhotos: return .purple
        case .largeFiles: return .orange
        case .virus: return .red
        case .startupItems: return .yellow
        case .performanceApps: return .green
        case .appUpdates: return .cyan
        }
    }
    
    // 获取该主分类下的子分类
    var subcategories: [CleanerCategory] {
        switch self {
        case .systemJunk:
            return [.userCache, .systemCache, .oldUpdates, 
                    .trash, // Add Trash here
                    .systemLogs, .userLogs]
        case .duplicates:
            return [.duplicates]
        case .similarPhotos:
            return [.similarPhotos]
        case .largeFiles:
            return [.largeFiles]
        case .virus:
            return [.virus]
        case .startupItems:
            return [.startupItems]
        case .performanceApps:
            return [.performanceApps]
        case .appUpdates:
            return [.appUpdates]
        }
    }
}

// MARK: - 清理类型
enum CleanerCategory: String, CaseIterable {
    // 系统垃圾类别（新增）
    case systemJunk = "系统垃圾"
    case systemCache = "系统缓存文件"
    case oldUpdates = "安装残留与旧备份"
    case userCache = "用户缓存文件"
    case trash = "废纸篓" // Add Trash case
    // languageFiles 已删除 - 删除 .lproj 会破坏应用签名
    case systemLogs = "系统日志文件"
    case userLogs = "用户日志文件"
    // brokenLoginItems 已删除 - 不符合"只清理缓存"原则
    
    // 原有类别
    case duplicates = "重复文件"
    case similarPhotos = "相似照片"
    case localizations = "多语言文件"
    case largeFiles = "大文件"
    
    // 新增智能扫描类别
    case virus = "病毒防护"
    case appUpdates = "应用更新"
    case startupItems = "开机启动"
    case performanceApps = "性能优化"
    
    var icon: String {
        switch self {
        case .systemJunk: return "globe"
        case .systemCache: return "internaldrive"
        case .oldUpdates: return "arrow.down.circle"
        case .userCache: return "person.crop.circle"
        case .trash: return "trash" // Trash icon
        case .systemLogs: return "doc.text"
        case .userLogs: return "person.text.rectangle"
        case .duplicates: return "doc.on.doc"
        case .similarPhotos: return "photo.on.rectangle"
        case .localizations: return "alphabet"
        case .largeFiles: return "doc"
        case .virus: return "shield.lefthalf.filled"
        case .appUpdates: return "arrow.clockwise.circle"
        case .startupItems: return "apps.ipad"
        case .performanceApps: return "bolt.fill"
        }
    }
    
    var englishName: String {
        switch self {
        case .systemJunk: return "System Junk"
        case .systemCache: return "System Cache"
        case .oldUpdates: return "Installation Residues & Old Backups"
        case .userCache: return "User Cache"
        case .trash: return "Trash"
        case .systemLogs: return "System Logs"
        case .userLogs: return "User Logs"
        case .duplicates: return "Duplicates"
        case .similarPhotos: return "Similar Photos"
        case .localizations: return "Localizations"
        case .largeFiles: return "Large Files"
        case .virus: return "Suspicious Items"
        case .appUpdates: return "App Updates"
        case .startupItems: return "Startup Items"
        case .performanceApps: return "Performance"
        }
    }

    func localizedName(for language: AppLanguage) -> String {
        if self == .virus {
            switch language {
            case .chinese: return "可疑项检查"
            case .traditionalChinese: return "可疑項目檢查"
            case .english: return "Suspicious Items"
            case .japanese: return "不審な項目"
            case .korean: return "의심 항목"
            case .russian: return "Подозрительные объекты"
            }
        }
        switch language {
        case .chinese:
            return rawValue
        case .traditionalChinese:
            switch self {
            case .systemJunk: return "系統垃圾"
            case .systemCache: return "系統快取"
            case .oldUpdates: return "安裝殘留與舊備份"
            case .userCache: return "使用者快取"
            case .trash: return "廢紙簍"
            case .systemLogs: return "系統日誌"
            case .userLogs: return "使用者日誌"
            case .duplicates: return "重複檔案"
            case .similarPhotos: return "相似照片"
            case .localizations: return "語言資源"
            case .largeFiles: return "大型檔案"
            case .virus: return "病毒防護"
            case .appUpdates: return "應用程式更新"
            case .startupItems: return "啟動項目"
            case .performanceApps: return "效能最佳化"
            }
        case .english:
            return englishName
        case .japanese:
            switch self {
            case .systemJunk: return "システムジャンク"
            case .systemCache: return "システムキャッシュ"
            case .oldUpdates: return "インストール残留物と古いバックアップ"
            case .userCache: return "ユーザーキャッシュ"
            case .trash: return "ゴミ箱"
            case .systemLogs: return "システムログ"
            case .userLogs: return "ユーザーログ"
            case .duplicates: return "重複ファイル"
            case .similarPhotos: return "類似写真"
            case .localizations: return "言語リソース"
            case .largeFiles: return "大容量ファイル"
            case .virus: return "ウイルス対策"
            case .appUpdates: return "アプリのアップデート"
            case .startupItems: return "起動項目"
            case .performanceApps: return "パフォーマンス"
            }
        case .korean:
            switch self {
            case .systemJunk: return "시스템 정크"
            case .systemCache: return "시스템 캐시"
            case .oldUpdates: return "설치 잔여물 및 이전 백업"
            case .userCache: return "사용자 캐시"
            case .trash: return "휴지통"
            case .systemLogs: return "시스템 로그"
            case .userLogs: return "사용자 로그"
            case .duplicates: return "중복 파일"
            case .similarPhotos: return "유사한 사진"
            case .localizations: return "언어 리소스"
            case .largeFiles: return "대용량 파일"
            case .virus: return "바이러스 보호"
            case .appUpdates: return "앱 업데이트"
            case .startupItems: return "시작 항목"
            case .performanceApps: return "성능 최적화"
            }
        case .russian:
            switch self {
            case .systemJunk: return "Системный мусор"
            case .systemCache: return "Системный кэш"
            case .oldUpdates: return "Остатки установки и старые резервные копии"
            case .userCache: return "Пользовательский кэш"
            case .trash: return "Корзина"
            case .systemLogs: return "Системные журналы"
            case .userLogs: return "Пользовательские журналы"
            case .duplicates: return "Дубликаты"
            case .similarPhotos: return "Похожие фотографии"
            case .localizations: return "Языковые ресурсы"
            case .largeFiles: return "Большие файлы"
            case .virus: return "Защита от вирусов"
            case .appUpdates: return "Обновления приложений"
            case .startupItems: return "Объекты автозапуска"
            case .performanceApps: return "Производительность"
            }
        }
    }
    
    var color: Color {
        switch self {
        case .systemJunk: return .pink
        case .systemCache: return .blue
        case .oldUpdates: return .orange
        case .userCache: return .cyan
        case .trash: return .gray
        case .systemLogs: return .green
        case .userLogs: return .teal
        case .duplicates: return .blue
        case .similarPhotos: return .purple
        case .localizations: return .orange
        case .largeFiles: return .pink
        case .virus: return .purple
        case .appUpdates: return .blue
        case .startupItems: return .orange
        case .performanceApps: return .green
        }
    }
    
    /// 是否是系统垃圾子类别
    var isSystemJunkSubcategory: Bool {
        switch self {
        case .systemCache, .oldUpdates, .userCache, .trash, .systemLogs, .userLogs:
            return true
        default:
            return false
        }
    }
}

// MARK: - 文件项
struct CleanerFileItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    /// Scan-time identity for display accounting. Never resolve paths while
    /// SwiftUI is rendering; deletion still resolves and checks the live URL.
    let canonicalPath: String
    let name: String
    let size: Int64
    var isSelected: Bool = true  // 默认全选
    let groupId: String  // 用于分组显示
    let isDirectory: Bool
    let installationResidue: InstallationResidue?
    
    // 用于树形展示的自引用
    var children: [CleanerFileItem]? = nil
    
    init(url: URL, name: String, size: Int64, groupId: String, isDirectory: Bool? = nil, isSelected: Bool = true, installationResidue: InstallationResidue? = nil) {
        self.url = url
        self.canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        self.name = name
        self.size = size
        self.groupId = groupId
        self.installationResidue = installationResidue
        // A discovered installation residue always requires manual selection.
        self.isSelected = installationResidue == nil ? isSelected : false
        if let isDir = isDirectory {
            self.isDirectory = isDir
        } else {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            self.isDirectory = isDir.boolValue
        }
    }
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
    
    static func == (lhs: CleanerFileItem, rhs: CleanerFileItem) -> Bool {
        lhs.url == rhs.url
    }
}

// MARK: - 重复文件组
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let hash: String
    var files: [CleanerFileItem]
    
    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }
    
    var wastedSize: Int64 {
        // 保留一个，其他都是浪费
        guard files.count > 1 else { return 0 }
        return files.dropFirst().reduce(0) { $0 + $1.size }
    }
}

// MARK: - 应用缓存分组
class AppCacheGroup: Identifiable, ObservableObject {
    let id = UUID()
    let appName: String
    let bundleId: String?
    let icon: NSImage
    @Published var files: [CleanerFileItem] {
        didSet { filesDidChange?() }
    }
    fileprivate var filesDidChange: (() -> Void)?
    @Published var isExpanded: Bool = false
    
    init(appName: String, bundleId: String?, icon: NSImage, files: [CleanerFileItem]) {
        self.appName = appName
        self.bundleId = bundleId
        self.icon = icon
        self.files = files
    }
    
    var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }
    
    var selectedSize: Int64 {
        files.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
}

private enum SmartScanSession {
    @TaskLocal static var id: UUID?
}

/// Value-only input for background reconciliation; no observable group or
/// service is read by the worker.
private struct SmartJunkFileSnapshot: Sendable {
    let id: UUID
    let path: String
}

// MARK: - 智能清理服务
class SmartCleanerService: ObservableObject {

    private let cleanupFile: (URL, Bool) async -> Bool
    private let deletionAllowed: (URL, Bool) -> Bool
    private let junkRootSelector: @Sendable ([String]) -> [String]
    private let installationResidueScan: (() async -> [InstallationResidue])?
    private let installationResidueValidator: (InstallationResidue) async -> Bool

    init(cleanupFile: @escaping (URL, Bool) async -> Bool = { url, permanent in
        // Generic cleanup always moves to Trash. Emptying Trash belongs to its
        // dedicated flow, where the user explicitly confirms permanent removal.
        guard !permanent else { return false }
        return DeletionLogService.shared.logAndDelete(at: url, category: "SmartClean")
    }, deletionAllowed: @escaping (URL, Bool) -> Bool = {
        SafetyGuard.shared.isSafeToDelete($0, ignoreProtection: $1)
    }, junkRootSelector: @escaping @Sendable ([String]) -> [String] = {
        CleanupFileSystem.uniqueRootPaths($0)
    }, installationResidueScan: (() async -> [InstallationResidue])? = nil,
       installationResidueValidator: @escaping (InstallationResidue) async -> Bool = {
        await SafetyGuard.shared.isSafeToDeleteInstallationResidue($0)
    }) {
        self.cleanupFile = cleanupFile
        self.deletionAllowed = deletionAllowed
        self.junkRootSelector = junkRootSelector
        self.installationResidueScan = installationResidueScan
        self.installationResidueValidator = installationResidueValidator
    }
    
    // MARK: - 选中状态枚举
    enum SelectionState {
        case none      // 全部未选中
        case partial   // 部分选中（半勾选）
        case all       // 全部选中
    }
    
    // 按应用分组的缓存结果 (针对 userCache)
    @Published var appCacheGroups: [AppCacheGroup] = [] {
        didSet {
            for group in oldValue { group.filesDidChange = nil }
            for group in appCacheGroups {
                group.filesDidChange = { [weak self] in
                    guard let self else { return }
                    self.junkResultsDidChange()
                    if self.junkUpdateDepth == 0 { self.objectWillChange.send() }
                }
            }
            junkResultsDidChange()
        }
    }
    
    // 原有属性
    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var similarPhotoGroups: [DuplicateGroup] = []
    @Published var localizationFiles: [CleanerFileItem] = []
    @Published var largeFiles: [CleanerFileItem] = []
    
    // 新增系统垃圾属性
    @Published var systemCacheFiles: [CleanerFileItem] = [] { didSet { junkResultsDidChange() } }
    @Published var oldUpdateFiles: [CleanerFileItem] = [] { didSet { junkResultsDidChange() } }
    @Published var userCacheFiles: [CleanerFileItem] = [] { didSet { junkResultsDidChange() } }
    @Published var trashFiles: [CleanerFileItem] = [] // New property
    // languageFiles 已删除 - 会破坏应用签名
    @Published var systemLogFiles: [CleanerFileItem] = [] { didSet { junkResultsDidChange() } }
    @Published var userLogFiles: [CleanerFileItem] = [] { didSet { junkResultsDidChange() } }
    // brokenLoginItems 已删除 - 不符合"只清理缓存"原则
    
    // 扫描状态追踪 (针对 8 大分类)
    @Published var scannedCategories: Set<CleanerCategory> = []
    
    // 新增智能扫描结果
    @Published var virusThreats: [DetectedThreat] = []
    @Published var startupItems: [LaunchItem] = []
    @Published var performanceApps: [PerformanceAppItem] = []
    @Published var hasAppUpdates: Bool = false
    
    // 统计数据 (用于结果页)
    /// Logical bytes processed, not physical disk space reclaimed.
    @Published var totalCleanedSize: Int64 = 0
    @Published var totalMovedToTrashSize: Int64 = 0
    @Published var observedDiskSpaceChange: Int64?
    @Published private(set) var lastFailedCleanupFiles: [CleanerFileItem] = []
    @Published var totalResolvedThreats: Int = 0
    @Published var totalOptimizedItems: Int = 0
    
    // 子服务实例
    private let malwareScanner = MalwareScanner()
    private let systemOptimizer = SystemOptimizer()
    private let updateChecker = UpdateCheckerService.shared
    
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var currentScanPath: String = ""
    @Published var currentCategory: CleanerCategory = .systemJunk
    
    // Global progress range for sub-scans
    private var progressRange: (start: Double, end: Double) = (0.0, 1.0)
    
    // Helper to update progress based on current range (Must be called on MainActor)
    private func setProgress(_ localProgress: Double) {
        let range = progressRange.end - progressRange.start
        let val = progressRange.start + (localProgress * range)
        // Ensure strictly increasing (optional, but good for UX)
        if val > self.scanProgress {
            self.scanProgress = val
        } else if localProgress == 0 {
             // Allow backward jump only if localProgress is 0 (start of new phase)
             // But actually we usually want to start at the range start.
             self.scanProgress = progressRange.start
        }
    }
    
    // 停止扫描标志
    @MainActor private var activeScanID: UUID?
    private let scanStopLock = NSLock()
    private var scanStopRequested = false
    private var lastScanPathPublish = Date.distantPast
    private var cleaningStopRequested = false

    private func setCleaningCancelled(_ value: Bool) {
        scanStopLock.lock()
        cleaningStopRequested = value
        scanStopLock.unlock()
    }

    private func isCleaningCancelled() -> Bool {
        scanStopLock.lock()
        defer { scanStopLock.unlock() }
        return cleaningStopRequested
    }
    private var shouldStopScanning: Bool {
        get { scanStopLock.lock(); defer { scanStopLock.unlock() }; return scanStopRequested }
        set {
            scanStopLock.lock()
            scanStopRequested = newValue
            if !newValue { lastScanPathPublish = .distantPast }
            scanStopLock.unlock()
        }
    }
    
    // 停止扫描方法
    @MainActor
    func stopScanning() {
        shouldStopScanning = true
        malwareScanner.stopScan()
        currentScanPath = ""
    }
    
    private let fileManager = FileManager.default
    
    // 保留的语言
    private let keepLocalizations = ["en.lproj", "Base.lproj", "zh-Hans.lproj", "zh-Hant.lproj", "zh_CN.lproj", "zh_TW.lproj", "Chinese.lproj", "English.lproj"]
    
    // 默认扫描目录
    private var scanDirectories: [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Pictures")
        ]
    }
    
    private func claimScanPathUpdate() -> Bool {
        scanStopLock.lock()
        defer { scanStopLock.unlock() }
        let now = Date()
        guard !scanStopRequested && now.timeIntervalSince(lastScanPathPublish) >= 0.1 else { return false }
        lastScanPathPublish = now
        return true
    }

    private func publishScanPath(_ path: String) async {
        guard claimScanPathUpdate(), !Task.isCancelled else { return }
        await MainActor.run {
            guard isScanning && !shouldStopScanning else { return }
            currentScanPath = path
        }
    }

    private func withScanSession(_ operation: @escaping () async -> Void) async {
        let id = SmartScanSession.id ?? UUID()
        let state = await MainActor.run { () -> (allowed: Bool, ownsSession: Bool) in
            if let activeScanID { return (activeScanID == id, false) }
            guard !isCleaning && !Task.isCancelled else { return (false, false) }
            activeScanID = id
            shouldStopScanning = false
            isScanning = true
            return (true, true)
        }
        guard state.allowed else { return }
        if !shouldStopScanning && !Task.isCancelled {
            await SmartScanSession.$id.withValue(id) { await operation() }
        }
        if state.ownsSession {
            await MainActor.run {
                guard activeScanID == id else { return }
                activeScanID = nil
                isScanning = false
                currentScanPath = ""
            }
        }
    }

    // MARK: - Cached display statistics
    private var cachedJunkSizes: [CleanerCategory: Int64] = [:]
    private var cachedJunkCounts: [CleanerCategory: Int] = [:]
    private var junkUpdateDepth = 0
    private var junkSummaryNeedsRefresh = false
    private var junkResultRevision: UInt64 = 0
    private(set) var junkSummaryBuildCount = 0

    /// These getters are used many times per SwiftUI layout. They must remain
    /// constant-time and must never normalize, resolve, or deduplicate paths.
    var systemJunkTotalSize: Int64 { cachedJunkSizes[.systemJunk, default: 0] }
    var hasJunkResults: Bool { cachedJunkCounts[.systemJunk, default: 0] > 0 }

    private func junkResultsDidChange() {
        junkResultRevision &+= 1
        junkSummaryNeedsRefresh = true
        if junkUpdateDepth == 0 { rebuildJunkSummary() }
    }

    private func beginJunkUpdates() { junkUpdateDepth += 1 }

    private func endJunkUpdates() {
        junkUpdateDepth -= 1
        if junkUpdateDepth == 0 && junkSummaryNeedsRefresh {
            rebuildJunkSummary()
            objectWillChange.send()
        }
    }

    private func rebuildJunkSummary() {
        let userFiles = userCacheFiles + appCacheGroups.flatMap(\.files)
        let categories: [(CleanerCategory, [CleanerFileItem])] = [
            (.systemCache, systemCacheFiles), (.oldUpdates, oldUpdateFiles),
            (.userCache, userFiles), (.systemLogs, systemLogFiles), (.userLogs, userLogFiles)
        ]
        var sizes: [CleanerCategory: Int64] = [:]
        var counts: [CleanerCategory: Int] = [:]
        for (category, files) in categories {
            sizes[category] = Self.selectedJunkSize(files)
            counts[category] = files.count
        }
        // Cross-category parents and duplicates are counted only once.
        sizes[.systemJunk] = Self.selectedJunkSize(categories.flatMap { $0.1 })
        counts[.systemJunk] = categories.reduce(0) { $0 + $1.1.count }
        cachedJunkSizes = sizes
        cachedJunkCounts = counts
        junkSummaryNeedsRefresh = false
        junkSummaryBuildCount += 1
    }

    private static func selectedJunkSize(_ files: [CleanerFileItem]) -> Int64 {
        let roots = Set(CleanupFileSystem.uniqueRootPaths(Array(files.lazy.filter(\.isSelected).map(\.canonicalPath))))
        var seen = Set<String>()
        var size: Int64 = 0
        for file in files where file.isSelected && roots.contains(file.canonicalPath) {
            guard seen.insert(file.canonicalPath).inserted else { continue }
            let bytes = max(0, file.size)
            size = size > Int64.max - bytes ? Int64.max : size + bytes
        }
        return size
    }
    
    private var allJunkFiles: [CleanerFileItem] {
        systemCacheFiles + oldUpdateFiles + userCacheFiles + systemLogFiles + userLogFiles + appCacheGroups.flatMap(\.files)
    }

    static func uniqueFiles(_ files: [CleanerFileItem]) -> [CleanerFileItem] {
        // Cleanup requires fresh canonical paths, unlike display accounting.
        let paths = files.map { $0.url.standardizedFileURL.resolvingSymlinksInPath().path }
        let rootPaths = Set(CleanupFileSystem.uniqueRootPaths(paths))
        var seen = Set<String>()
        return zip(files, paths).compactMap { file, path in
            rootPaths.contains(path) && seen.insert(path).inserted ? file : nil
        }
    }

    private static func uniqueFilesForCleanup(_ files: [CleanerFileItem]) async -> [CleanerFileItem] {
        await Task.detached(priority: .utility) { uniqueFiles(files) }.value
    }

    @MainActor
    func deduplicateJunkResults() async {
        let revision = junkResultRevision
        let session = activeScanID
        let snapshot = allJunkFiles.filter {
            $0.installationResidue != nil || !InstallationResidueScanner.excludesGenericCleanup($0.url)
        }.map { SmartJunkFileSnapshot(id: $0.id, path: $0.canonicalPath) }
        let selectRoots = junkRootSelector
        let retainedIDs = await Task.detached(priority: .utility) {
            let roots = Set(selectRoots(snapshot.map(\.path)))
            var seen = Set<String>()
            return Set(snapshot.compactMap { file in
                roots.contains(file.path) && seen.insert(file.path).inserted ? file.id : nil
            })
        }.value
        // A stopped scan or a new selection/result publication must not be
        // overwritten by an older worker's answer.
        guard !shouldStopScanning && !Task.isCancelled,
              activeScanID == session, junkResultRevision == revision else { return }
        beginJunkUpdates()
        defer { endJunkUpdates() }
        var seen = Set<UUID>()
        let keep: (CleanerFileItem) -> Bool = {
            retainedIDs.contains($0.id) && seen.insert($0.id).inserted
        }
        systemCacheFiles = systemCacheFiles.filter(keep)
        oldUpdateFiles = oldUpdateFiles.filter(keep)
        userCacheFiles = userCacheFiles.filter(keep)
        systemLogFiles = systemLogFiles.filter(keep)
        userLogFiles = userLogFiles.filter(keep)
        for group in appCacheGroups { group.files = group.files.filter(keep) }
        appCacheGroups.removeAll { $0.files.isEmpty }
    }

    var virusTotalSize: Int64 {
        virusThreats.reduce(0) { $0 + $1.size }
    }
    
    // MARK: - 获取指定分类的大小
    func sizeFor(category: CleanerCategory) -> Int64 {
        switch category {
        case .systemJunk:
            return systemJunkTotalSize
        case .systemCache:
            return cachedJunkSizes[.systemCache, default: 0]
        case .oldUpdates:
            return cachedJunkSizes[.oldUpdates, default: 0]
        case .userCache:
            return cachedJunkSizes[.userCache, default: 0]
        case .trash:
            return trashFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        case .systemLogs:
            return cachedJunkSizes[.systemLogs, default: 0]
        case .userLogs:
            return cachedJunkSizes[.userLogs, default: 0]
        case .duplicates:
            return duplicateGroups.reduce(0) { $0 + $1.wastedSize }
        case .similarPhotos:
            return similarPhotoGroups.reduce(0) { $0 + $1.wastedSize }
        case .localizations:
            return localizationFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        case .largeFiles:
            return largeFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        case .virus:
            return virusTotalSize
        case .appUpdates:
            return 0 // 更新即使有大小也不计入清理大小，或者计入下载大小？暂时为0
        case .startupItems:
            return 0 // 启动项文件很小，可以忽略或计算 plist 大小
        case .performanceApps:
            return 0 // 进程内存不计入磁盘清理大小
        }
    }
    
    // MARK: - 获取指定分类的项目数
    func countFor(category: CleanerCategory) -> Int {
        switch category {
        case .systemJunk:
            return cachedJunkCounts[.systemJunk, default: 0]
        case .systemCache:
            return systemCacheFiles.count
        case .oldUpdates:
            return oldUpdateFiles.count
        case .userCache:
            return cachedJunkCounts[.userCache, default: 0]
        case .trash:
            return trashFiles.count
        case .systemLogs:
            return systemLogFiles.count
        case .userLogs:
            return userLogFiles.count
        case .duplicates:
            return duplicateGroups.flatMap { $0.files }.count
        case .similarPhotos:
            return similarPhotoGroups.flatMap { $0.files }.count
        case .localizations:
            return localizationFiles.count
        case .largeFiles:
            return largeFiles.count
        case .virus:
            return virusThreats.count
        case .appUpdates:
            return hasAppUpdates ? 1 : 0
        case .startupItems:
            return startupItems.count
        case .performanceApps:
            return performanceApps.count
        }
    }
    
    // MARK: - 切换文件选择状态
    @MainActor
    func toggleFileSelection(file: CleanerFileItem, in category: CleanerCategory) {
        beginJunkUpdates()
        defer { endJunkUpdates() }
        switch category {
        case .systemCache:
            if let idx = systemCacheFiles.firstIndex(where: { $0.url == file.url }) {
                systemCacheFiles[idx].isSelected.toggle()
            }
        case .oldUpdates:
            if let idx = oldUpdateFiles.firstIndex(where: { $0.url == file.url }) {
                oldUpdateFiles[idx].isSelected.toggle()
            }
        case .userCache:
            if let idx = userCacheFiles.firstIndex(where: { $0.url == file.url }) {
                userCacheFiles[idx].isSelected.toggle()
            }
            // 同时更新分组中的对应项，以确保 UI 同步 (CleanerFileItem 是 struct)
            for gIdx in appCacheGroups.indices {
                if let fIdx = appCacheGroups[gIdx].files.firstIndex(where: { $0.url == file.url }) {
                    appCacheGroups[gIdx].files[fIdx].isSelected.toggle()
                    // 关键修复: 手动触发 Group 的更新通知，确保 AppCacheGroupRow 刷新
                    appCacheGroups[gIdx].objectWillChange.send() 
                    break
                }
            }
            
            // 关键修复: 手动触发 Service 的更新通知，确保 Summary View 刷新统计数据
            self.objectWillChange.send()
        case .trash:
            if let idx = trashFiles.firstIndex(where: { $0.url == file.url }) {
                trashFiles[idx].isSelected.toggle()
            }
        case .systemLogs:
            if let idx = systemLogFiles.firstIndex(where: { $0.url == file.url }) {
                systemLogFiles[idx].isSelected.toggle()
            }
        case .userLogs:
            if let idx = userLogFiles.firstIndex(where: { $0.url == file.url }) {
                userLogFiles[idx].isSelected.toggle()
            }
        case .localizations:
            if let idx = localizationFiles.firstIndex(where: { $0.url == file.url }) {
                localizationFiles[idx].isSelected.toggle()
            }
        case .largeFiles:
            if let idx = largeFiles.firstIndex(where: { $0.url == file.url }) {
                largeFiles[idx].isSelected.toggle()
            }
        case .systemJunk, .duplicates, .similarPhotos, .virus, .appUpdates, .startupItems, .performanceApps:
            // 这些是复合分类，或不支持直接切换
            break
        }
    }
    
    /// 动态加载子文件夹内容
    func loadSubItems(for item: CleanerFileItem) async -> [CleanerFileItem] {
        guard item.isDirectory else { return [] }
        
        var subItems: [CleanerFileItem] = []
        do {
            let contents = try fileManager.contentsOfDirectory(at: item.url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles])
            for url in contents {
                let resources = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                let isDir = resources.isDirectory ?? false
                let size = isDir ? calculateSize(at: url) : Int64(resources.fileSize ?? 0)
                
                subItems.append(CleanerFileItem(
                    url: url,
                    name: url.lastPathComponent,
                    size: size,
                    groupId: item.groupId,
                    isDirectory: isDir
                ))
            }
        } catch {
            print("Failed to load sub items for \(item.url.path): \(error)")
        }
        
        return subItems.sorted { $0.size > $1.size }
    }
    
    /// 删除单个文件
    @MainActor
    func deleteSingleFile(_ file: CleanerFileItem, from category: CleanerCategory) async -> Bool {
        guard !isCleaning && !isScanning else { return false }
        isCleaning = true
        cleaningWasStopped = false
        setCleaningCancelled(false)
        let before = CleanupDiskSnapshot.capture()
        defer {
            isCleaning = false
            observedDiskSpaceChange = CleanupDiskSnapshot.capture()?.change(since: before)
        }
        guard await deleteCleanupFile(file, bypassProtection: category == .largeFiles) else { return false }
        removeCleanedFiles([file.url.standardizedFileURL.resolvingSymlinksInPath().path])
        totalMovedToTrashSize += file.size
        totalCleanedSize += file.size
        return true
    }

    /// 从分类数组中移除文件
    @MainActor
    private func removeFileFromCategory(_ file: CleanerFileItem, category: CleanerCategory) {
        beginJunkUpdates()
        defer { endJunkUpdates() }
        switch category {
        case .systemCache:
            systemCacheFiles.removeAll { $0.url == file.url }
        case .oldUpdates:
            oldUpdateFiles.removeAll { $0.url == file.url }
        case .userCache:
            userCacheFiles.removeAll { $0.url == file.url }
            // 同时更新分组中的该文件
            for gIdx in appCacheGroups.indices {
                appCacheGroups[gIdx].files.removeAll { $0.url == file.url }
            }
            // 移除空组
            appCacheGroups.removeAll { $0.files.isEmpty }
        case .trash:
            trashFiles.removeAll { $0.url == file.url }
        case .systemLogs:
            systemLogFiles.removeAll { $0.url == file.url }
        case .userLogs:
            userLogFiles.removeAll { $0.url == file.url }
        case .localizations:
            localizationFiles.removeAll { $0.url == file.url }
        case .largeFiles:
            largeFiles.removeAll { $0.url == file.url }
        default:
            break
        }
    }

    /// Removes an ignored result from every live representation without
    /// touching the file on disk. Future scans also consult the shared store.
    @MainActor
    func ignoreFile(_ file: CleanerFileItem, in category: CleanerCategory) {
        ScanResultIgnoreStore.shared.ignore(file.url)
        removeFileFromCategory(file, category: category)
    }
    
    // MARK: - 主分类支持方法
    
    /// 获取分类对应的文件列表
    @MainActor
    func filesFor(category: CleanerCategory) -> [CleanerFileItem] {
        switch category {
        case .userCache: return userCacheFiles + appCacheGroups.flatMap { $0.files }
        case .trash: return trashFiles
        case .systemCache: return systemCacheFiles
        case .oldUpdates: return oldUpdateFiles
        case .systemLogs: return systemLogFiles
        case .userLogs: return userLogFiles
        case .duplicates: return duplicateGroups.flatMap { $0.files }
        case .similarPhotos: return similarPhotoGroups.flatMap { $0.files }
        case .largeFiles: return largeFiles
        case .localizations: return localizationFiles
        default: return []
        }
    }
    
    /// 获取主分类的统计信息
    @MainActor
    func statisticsFor(mainCategory: MainCategory) -> (count: Int, size: Int64) {
        var totalCount = 0
        var totalSize: Int64 = 0
        
        for category in mainCategory.subcategories {
            let stats = statisticsFor(category: category)
            totalCount += stats.count
            totalSize += stats.size
        }
        
        return (totalCount, totalSize)
    }
    
    /// 获取子分类的统计信息
    @MainActor
    func statisticsFor(category: CleanerCategory) -> (count: Int, size: Int64) {
        switch category {
        case .startupItems:
            let count = startupItems.filter { $0.isSelected }.count
            return (count, 0)
        case .virus:
            let count = virusThreats.count // Threat usually doesn't have selection logic same way, or implies all.
            // But verify if virusThreats has isSelected. Assuming yes given the pattern, or just count all.
            // Actually, in dashboard we show total count.
             return (count, 0)
        case .performanceApps:
            let count = performanceApps.filter { $0.isSelected }.count
            return (count, performanceApps.filter { $0.isSelected }.reduce(0) { $0 + $1.memoryUsage })
        default:
            let files = filesFor(category: category).filter { $0.isSelected }
            return (files.count, files.reduce(0) { $0 + $1.size })
        }
    }
    
    // MARK: - 选中状态检测
    
    /// 检查子分类的勾选状态
    @MainActor
    func getSelectionState(for category: CleanerCategory) -> SelectionState {
        switch category {
        case .performanceApps:
            guard !performanceApps.isEmpty else { return .none }
            let selectedCount = performanceApps.filter { $0.isSelected }.count
            if selectedCount == 0 { return .none }
            if selectedCount == performanceApps.count { return .all }
            return .partial
        default:
            let files = filesFor(category: category)
            guard !files.isEmpty else { return .none }
            
            let selectedCount = files.filter { $0.isSelected }.count
            if selectedCount == 0 { return .none }
            if selectedCount == files.count { return .all }
            return .partial
        }
    }

    /// 检查主分类的勾选状态
    @MainActor
    func getSelectionState(for mainCategory: MainCategory) -> SelectionState {
        var totalItems = 0
        var selectedItems = 0
        
        for category in mainCategory.subcategories {
            switch category {
            case .performanceApps:
                totalItems += performanceApps.count
                selectedItems += performanceApps.filter { $0.isSelected }.count
            default:
                let files = filesFor(category: category)
                totalItems += files.count
                selectedItems += files.filter { $0.isSelected }.count
            }
        }
        
        guard totalItems > 0 else { return .none }
        if selectedItems == 0 { return .none }
        if selectedItems == totalItems { return .all }
        return .partial
    }
    
    /// 切换主分类选中状态
    @MainActor
    func toggleMainCategorySelection(_ mainCategory: MainCategory) {
        beginJunkUpdates()
        defer { endJunkUpdates() }
        let currentState = getSelectionState(for: mainCategory)
        // 如果当前是全部选中，则取消全选；否则（部分选中或未选中）全选
        let newSelected = (currentState != .all)
        
        for category in mainCategory.subcategories {
            toggleCategorySelection(category, forceTo: newSelected)
        }
        
        // 确保触发更新
        objectWillChange.send()
    }
    
    /// 切换应用分组的选中状态（同步更新 userCacheFiles）
    @MainActor
    func toggleAppGroupSelection(_ group: AppCacheGroup) {
        beginJunkUpdates()
        defer { endJunkUpdates() }
        // 计算新状态：只要不是全选，就设为全选（如果是部分选中，操作是补全选中）
        // 或者：只要是全选，就取消；否则全选。
        // Finder逻辑：点击Checkbox时，如果是混合状态，通常变为全选或全不选。
        // 根据 SelectionState 逻辑：
        // State is All -> Toggle to None
        // State is None -> Toggle to All
        // State is Partial -> Toggle to All
        
        let allSelected = group.files.allSatisfy { $0.isSelected }
        let targetState = !allSelected
        
        // 1. 更新 Group 内的文件状态 (引用类型直接更新)
        group.files = Self.settingSelection(group.files, to: targetState)
        
        // 2. 同步更新 userCacheFiles (打平的列表)
        // 建立 Group 文件 URL 集合以加速查找
        let groupURLs = Set(group.files.map { $0.url })
        var updated = userCacheFiles
        for i in updated.indices where groupURLs.contains(updated[i].url) {
            updated[i].isSelected = targetState
        }
        userCacheFiles = updated
        
        objectWillChange.send()
    }
    
    /// 切换整个子分类的选中状态
    @MainActor
    func toggleCategorySelection(_ category: CleanerCategory, forceTo: Bool? = nil) {
        beginJunkUpdates()
        defer { endJunkUpdates() }
        let files = filesFor(category: category)
        // 如果提供了强制状态则使用之，否则反转当前全选状态
        let targetState: Bool
        if let force = forceTo {
            targetState = force
        } else {
            // 对于 performanceApps，需要单独判断
            if category == .performanceApps {
                targetState = !performanceApps.allSatisfy { $0.isSelected }
            } else {
                targetState = !files.allSatisfy { $0.isSelected }
            }
        }
        
        // 全选或全不选
        switch category {
        case .systemCache:
            systemCacheFiles = Self.settingSelection(systemCacheFiles, to: targetState)
        case .oldUpdates:
            oldUpdateFiles = Self.settingSelection(oldUpdateFiles, to: targetState)
        case .userCache:
            userCacheFiles = Self.settingSelection(userCacheFiles, to: targetState)
            // 同时更新分组
            for gIdx in appCacheGroups.indices {
                appCacheGroups[gIdx].files = Self.settingSelection(appCacheGroups[gIdx].files, to: targetState)
            }
        case .trash:
            for i in trashFiles.indices {
                trashFiles[i].isSelected = targetState
            }
        case .systemLogs:
            systemLogFiles = Self.settingSelection(systemLogFiles, to: targetState)
        case .userLogs:
            userLogFiles = Self.settingSelection(userLogFiles, to: targetState)
        case .largeFiles:
            for i in largeFiles.indices {
                largeFiles[i].isSelected = targetState
            }
        case .duplicates:
            for gIdx in duplicateGroups.indices {
                for fIdx in duplicateGroups[gIdx].files.indices {
                    duplicateGroups[gIdx].files[fIdx].isSelected = targetState
                }
            }
        case .similarPhotos:
            for gIdx in similarPhotoGroups.indices {
                for fIdx in similarPhotoGroups[gIdx].files.indices {
                    similarPhotoGroups[gIdx].files[fIdx].isSelected = targetState
                }
            }
        case .performanceApps:
            for i in performanceApps.indices {
                performanceApps[i].isSelected = targetState
            }
        default:
            break
        }
        
        // 手动触发ObservableObject更新，因为修改数组元素的属性不会自动触发
        objectWillChange.send()
    }

    private static func settingSelection(_ files: [CleanerFileItem], to selected: Bool) -> [CleanerFileItem] {
        var updated = files
        for index in updated.indices { updated[index].isSelected = selected }
        return updated
    }
    
    /// 检查子分类是否全选
    @MainActor
    func isCategoryAllSelected(_ category: CleanerCategory) -> Bool {
        switch category {
        case .performanceApps:
            guard !performanceApps.isEmpty else { return false }
            return performanceApps.allSatisfy { $0.isSelected }
        default:
            let files = filesFor(category: category)
            guard !files.isEmpty else { return false }
            return files.allSatisfy { $0.isSelected }
        }
    }
    
    // MARK: - 扫描系统垃圾
    func scanSystemJunk() async {
        await withScanSession { await self.performScanSystemJunk() }
    }

    private func performScanSystemJunk() async {
        await MainActor.run {
            beginJunkUpdates()
            defer { endJunkUpdates() }
            isScanning = true
            // Remove unconditional reset to 0
            if progressRange == (0.0, 1.0) {
                 setProgress(0)
            }
            currentCategory = .systemJunk
            systemCacheFiles = []
            oldUpdateFiles = []
            userCacheFiles = []
            trashFiles = []
            systemLogFiles = []
            userLogFiles = []
            appCacheGroups = []
        }
        
        let totalSteps = 7.0
        var currentStep = 0.0
        
        // 1. 扫描系统缓存
        await updateProgress(step: currentStep, total: totalSteps, message: "正在扫描系统缓存...")
        let sysCache = await scanSystemCache()
        await MainActor.run { systemCacheFiles = visible(sysCache) }
        currentStep += 1
        
        // Only recognized installation leftovers; never broad system updates
        // or ordinary Downloads. All candidates remain unselected for review.
        await updateProgress(step: currentStep, total: totalSteps, message: "正在检查安装残留与旧备份...")
        let residues = await scanInstallationResidues()
        await MainActor.run { oldUpdateFiles = visible(residues) }
        currentStep += 1
        
        // 3. 扫描用户缓存
        await updateProgress(step: currentStep, total: totalSteps, message: "正在扫描用户缓存...")
        let usrCache = await scanUserCache()
        await MainActor.run { userCacheFiles = visible(usrCache) }
        currentStep += 1
        
        // Trash is handled only by the dedicated module and confirmation.

        // 4. 扫描语言文件 - ⚠️ 已禁用(用户要求只清理缓存和日志)
        // await updateProgress(step: currentStep, total: totalSteps, message: "正在扫描语言文件...")
        // let langFiles = await scanLanguageFiles()
        // await MainActor.run { languageFiles = langFiles }
        // currentStep += 1
        
        // 5. 扫描系统日志
        await updateProgress(step: currentStep, total: totalSteps, message: "正在扫描系统日志...")
        let sysLogs = await scanSystemLogs()
        await MainActor.run { systemLogFiles = visible(sysLogs) }
        currentStep += 1
        
        // 6. 扫描用户日志
        await updateProgress(step: currentStep, total: totalSteps, message: "正在扫描用户日志...")
        let usrLogs = await scanUserLogs()
        await MainActor.run { userLogFiles = visible(usrLogs) }
        currentStep += 1
        
        // 7. 扫描损坏的登录项 - ⚠️ 已禁用(用户要求只清理缓存和日志)
        // await updateProgress(step: currentStep, total: totalSteps, message: "正在扫描损坏的登录项...")
        // let brokenItems = await scanBrokenLoginItems()
        // await MainActor.run { brokenLoginItems = brokenItems }
        
        await deduplicateJunkResults()
        await MainActor.run { currentScanPath = "" }
    }
    
    private func updateProgress(step: Double, total: Double, message: String) async {
        await MainActor.run {
            setProgress(step / total)
            currentScanPath = message
        }
    }

    private nonisolated func visible(_ items: [CleanerFileItem]) -> [CleanerFileItem] {
        items.filter {
            ScanResultIgnoreStore.shouldInclude($0.url) &&
            ($0.installationResidue != nil || !InstallationResidueScanner.excludesGenericCleanup($0.url))
        }
    }
    
    // MARK: - 系统缓存扫描 (全面扫描系统级缓存)
    private func scanSystemCache() async -> [CleanerFileItem] {
        var items: [CleanerFileItem] = []
        let home = fileManager.homeDirectoryForCurrentUser
        
        // 1. 扫描系统级 /Library/Caches（需要权限）
        let systemCachePaths = [
            "/Library/Caches"
            // "/private/var/folders"  // 移除: 避免与 Step 4 重复统计，且顶级目录扫描不准确
        ]
        
        for systemPath in systemCachePaths {
            let url = URL(fileURLWithPath: systemPath)
            if fileManager.isReadableFile(atPath: url.path) {
                if let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                    for itemURL in contents {
                        await self.publishScanPath(itemURL.path)
                        let size = calculateSize(at: itemURL)
                        // 优化：取消大小限制，确保扫描所有缓存
                        if size > 0 { 
                            items.append(CleanerFileItem(
                                url: itemURL,
                                name: "系统: " + itemURL.lastPathComponent,
                                size: size,
                                groupId: "systemCache"
                            ))
                        }
                    }
                }
            }
        }
        
        // 2. 扫描开发者缓存（通常非常大）
        let developerCaches = [
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport"),
            home.appendingPathComponent("Library/Developer/Xcode/watchOS DeviceSupport"),
            home.appendingPathComponent("Library/Developer/Xcode/tvOS DeviceSupport"),
            home.appendingPathComponent("Library/Developer/CoreSimulator/Caches"),
            home.appendingPathComponent("Library/Caches/com.apple.dt.Xcode"),
            // CocoaPods
            home.appendingPathComponent("Library/Caches/CocoaPods"),
            // npm/yarn/pnpm
            home.appendingPathComponent(".npm/_cacache"),
            home.appendingPathComponent("Library/Caches/Yarn"),
            // Gradle/Maven
            home.appendingPathComponent(".gradle/caches"),
            // Homebrew
            home.appendingPathComponent("Library/Caches/Homebrew"),
            // pip
            home.appendingPathComponent("Library/Caches/pip"),
            // Go
            home.appendingPathComponent("go/pkg/mod/cache")
        ]
        
        for devCacheURL in developerCaches {
            await self.publishScanPath(devCacheURL.path)
            if fileManager.fileExists(atPath: devCacheURL.path) {
                let size = calculateSize(at: devCacheURL)
                if size > 10 * 1024 { // 降低到 10KB（开发者缓存通常较大）
                    items.append(CleanerFileItem(
                        url: devCacheURL,
                        name: "开发: " + devCacheURL.lastPathComponent,
                        size: size,
                        groupId: "systemCache"
                    ))
                }
            }
        }
        
        // 3. 扫描 Apple 系统服务缓存（大幅扩展，包含关键高价值缓存）
        let appleCaches = [
            // ===== 核心系统服务（高价值，通常数 GB）=====
            "com.apple.coresymbolicationd",     // 符号化缓存，可达 4GB+
            "com.apple.iconservices.store",     // 图标服务缓存，数百 MB
            "com.apple.bird",                   // iCloud 同步缓存
            "com.apple.CrashReporter",          // 崩溃报告缓存
            "com.apple.CoreSimulator",          // iOS 模拟器缓存（开发者）
            
            // ===== 图形与渲染 =====
            "com.apple.Metal",                  // Metal 图形缓存
            "com.apple.ImageIO",                // 图像处理缓存
            "com.apple.QuickLook.thumbnailcache", // QuickLook 缩略图
            
            // ===== WebKit 与网络 =====
            "com.apple.WebKit.Networking",      // WebKit 网络缓存
            "com.apple.WebKit.WebContent",      // WebKit 内容缓存
            "com.apple.nsurlsessiond",          // URL 会话缓存
            "com.apple.nsservicescache",        // 服务缓存
            
            // ===== 系统索引与搜索 =====
            "com.apple.Spotlight",              // Spotlight 索引缓存
            "com.apple.spotlightknowledge",     // Spotlight 知识库
            "com.apple.parsecd",                // 解析缓存
            
            // ===== 位置与隐私 =====
            "com.apple.routined",               // 位置服务缓存
            "com.apple.ap.adprivacyd",          // 广告隐私
            
            // ===== 系统应用 =====
            "com.apple.Safari",
            "com.apple.finder",
            "com.apple.LaunchServices",
            "com.apple.DiskImages",
            "com.apple.helpd",
            "com.apple.iCloudHelper",
            "com.apple.appstore",
            "com.apple.Music",
            "com.apple.Photos",
            "com.apple.mail",
            "com.apple.Maps",
            "com.apple.AddressBook",
            "com.apple.CalendarAgent",
            "com.apple.reminders",
            "com.apple.VoiceMemos",
            "com.apple.Notes",
            "com.apple.FaceTime",
            "com.apple.TV",
            
            // ===== 开发者工具 =====
            "com.apple.dt.Xcode",
            "com.apple.dt.instruments",
            
            // ===== 其他系统服务 =====
            "com.apple.preferencepanes.usercache",
            "com.apple.proactive.eventtracker",
            "CloudKit",
            "GeoServices",
            "FamilyCircle"
        ]
        
        let cacheBaseURL = home.appendingPathComponent("Library/Caches")
        for cacheName in appleCaches {
            let cacheURL = cacheBaseURL.appendingPathComponent(cacheName)
            if fileManager.fileExists(atPath: cacheURL.path) {
                let size = calculateSize(at: cacheURL)
                if size > 1024 { // 降低阈值到 1KB，捕获更多缓存
                    let displayName = cacheName
                        .replacingOccurrences(of: "com.apple.", with: "Apple ")
                    items.append(CleanerFileItem(
                        url: cacheURL,
                        name: displayName,
                        size: size,
                        groupId: "systemCache"
                    ))
                }
            }
        }
        
        // Only old regular files directly inside temporary roots are eligible.
        // Do not move session/build/download directories, regardless of their size.
        for root in TemporaryCleanupPolicy.roots {
            for url in TemporaryCleanupPolicy.eligibleFiles(in: root, shouldCancel: { self.shouldStopScanning || Task.isCancelled }) {
                let size = calculateSize(at: url)
                if size > 0 {
                    items.append(CleanerFileItem(url: url, name: "临时文件: " + url.lastPathComponent,
                                                 size: size, groupId: "systemCache"))
                }
            }
        }

        // Browser caches are scanned by their explicit Cache/GPUCache paths;
        // Service Worker roots contain persistent registrations and offline data.

        // 5. 扫描 Group Containers 缓存
        let groupContainersURL = home.appendingPathComponent("Library/Group Containers")
        if let groups = try? fileManager.contentsOfDirectory(at: groupContainersURL, includingPropertiesForKeys: nil) {
            for groupURL in groups {
                // 查找缓存目录
                for subdir in ["Library/Caches", "Caches", "Cache"] {
                    let cacheDir = groupURL.appendingPathComponent(subdir)
                    if fileManager.fileExists(atPath: cacheDir.path) {
                        let size = calculateSize(at: cacheDir)
                        if size > 100 * 1024 {
                            items.append(CleanerFileItem(
                                url: cacheDir,
                                name: "Group: " + groupURL.lastPathComponent,
                                size: size,
                                groupId: "systemCache"
                            ))
                        }
                    }
                }
            }
        }
        
        // 6. 已移除深度递归扫描 /private/var/folders - 避免与 Step 4 重复统计
        // (Step 4 已覆盖当前用户的 C/ 和 T/ 目录，包含绝大多数高价值缓存)
        
        return items.sorted { $0.size > $1.size }
    }
    
    // MARK: - Installation leftovers requiring manual review
    func scanInstallationResidues() async -> [CleanerFileItem] {
        let candidates: [InstallationResidue]
        if let installationResidueScan {
            candidates = await installationResidueScan()
        } else {
            candidates = await InstallationResidueScanner().scan(shouldCancel: {
                self.shouldStopScanning || Task.isCancelled
            })
        }
        guard !shouldStopScanning && !Task.isCancelled else { return [] }
        return candidates.map { candidate in
            CleanerFileItem(url: candidate.url, name: candidate.name, size: candidate.size,
                            groupId: "oldUpdates", isSelected: false, installationResidue: candidate)
        }
    }
    
    // MARK: - 用户缓存扫描 (全面扫描整个用户缓存目录 + 已安装应用缓存 + 卸载残留)
    private func scanUserCache() async -> [CleanerFileItem] {
        var items: [CleanerFileItem] = []
        let home = fileManager.homeDirectoryForCurrentUser
        
        // 获取所有已安装应用的信息
        let appInfo = getInstalledAppInfo()
        _ = appInfo.bundleIds // Suppress unused warning since usage is commented out
        
        // 临时存储应用分组数据
        var groupsMap: [String: AppCacheGroup] = [:] // Key: bundleId or lowerAppName
        
        // 辅助闭包：由路径或 ID 找出最匹配的应用信息
        let findAppInfo: (String) -> (name: String, path: URL, bundleId: String?)? = { id in
            let lowerId = id.lowercased()
            // 1. 尝试 Bundle ID 完全匹配
            if let info = appInfo.appMap[lowerId] { return info }
            
            // 2. 尝试寻找最佳（最长）匹配
            // 避免短词（如 "Google"）误匹配长词（如 "Google Antigravity" 应优先匹配 "Antigravity" 如果存在）
            var bestMatch: (info: (name: String, path: URL, bundleId: String?), score: Int)? = nil
            let minMatchLength = 3
            
            for (key, info) in appInfo.appMap {
                // key 必须足够长才允许被包含匹配
                if key.count < minMatchLength { continue }
                
                // 计算匹配分数 (key 长度)
                // 优先匹配更具体的应用名
                if lowerId.contains(key) {
                    // ID 包含 AppKey (e.g. com.google.Chrome contains Chrome)
                    let score = key.count
                    if score > (bestMatch?.score ?? 0) {
                        bestMatch = (info, score)
                    }
                } else if key.contains(lowerId) {
                    // AppKey 包含 ID (e.g. Google Chrome contains Chrome)
                    let score = lowerId.count
                    if score > (bestMatch?.score ?? 0) {
                        bestMatch = (info, score)
                    }
                }
            }
            return bestMatch?.info
        }
        
        // 辅助闭包：添加文件到组或散项
        let addItem: (CleanerFileItem, String) -> Void = { item, appIdentifier in
            if let info = findAppInfo(appIdentifier) {
                let groupKey = info.bundleId ?? info.name.lowercased()
                if let group = groupsMap[groupKey] {
                    group.files.append(item)
                    // groupsMap[groupKey] = group // 引用类型无需重新赋值
                } else {
                    let icon = NSWorkspace.shared.icon(forFile: info.path.path)
                    groupsMap[groupKey] = AppCacheGroup(
                        appName: info.name,
                        bundleId: info.bundleId,
                        icon: icon,
                        files: [item]
                    )
                }
            } else {
                // 找不到明确应用关联的，也尝试从 URL 获取图标并可能单独列出 (此处先加入全局 items)
                items.append(item)
            }
        }
        
        // 1. 扫描整个 ~/Library/Caches 目录
        // ⚠️ 扫描 Library/Caches 下的所有缓存
        let cacheURL = home.appendingPathComponent("Library/Caches")
        if let contents = try? fileManager.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil) {
            for itemURL in contents {
                let size = calculateSize(at: itemURL)
                // 优化：取消大小限制，确保扫描所有缓存
                if size > 0 {
                    let bundleId = itemURL.lastPathComponent
                    
                    let displayName = formatAppName(bundleId)
                    
                    let fileItem = CleanerFileItem(
                        url: itemURL,
                        name: displayName,
                        size: size,
                        groupId: "userCache",
                        isDirectory: true
                    )
                    
                    // 使用 addItem 进行分组
                    addItem(fileItem, bundleId)
                }
            }
        }
        
        // 2. 扫描 ~/Library/Containers 中的缓存
        // ⚠️ 安全改进：跳过已安装应用的容器缓存
        let containersURL = home.appendingPathComponent("Library/Containers")
        if let containers = try? fileManager.contentsOfDirectory(at: containersURL, includingPropertiesForKeys: nil) {
            for containerURL in containers {
                let bundleId = containerURL.lastPathComponent
                
                // ⚠️ 跳过已安装应用的容器缓存
                // if installedAppBundleIds.contains(bundleId.lowercased()) {
                //    continue
                // }
                
                let appName = formatAppName(bundleId)
                
                // 扫描容器的 Data/Library/Caches
                let containerCacheURL = containerURL.appendingPathComponent("Data/Library/Caches")
                if fileManager.fileExists(atPath: containerCacheURL.path) {
                    let size = calculateSize(at: containerCacheURL)
                    if size > 50 * 1024 {
                        let fileItem = CleanerFileItem(
                            url: containerCacheURL,
                            name: "\(appName) 容器缓存",
                            size: size,
                            groupId: "userCache"
                        )
                        addItem(fileItem, bundleId)
                    }
                }
                
                let containerTmpURL = containerURL.appendingPathComponent("Data/tmp")
                for url in TemporaryCleanupPolicy.eligibleFiles(in: containerTmpURL, shouldCancel: { self.shouldStopScanning || Task.isCancelled }) {
                    let size = calculateSize(at: url)
                    if size > 0 {
                        addItem(CleanerFileItem(url: url, name: "\(appName) 临时文件", size: size, groupId: "userCache"), bundleId)
                    }
                }
            }
        }
        
        // Saved Application State can contain recovery state; it is not junk.

        // 4. 扫描 ~/Library/Application Support 中的缓存目录
        // ⚠️ 安全改进：跳过已安装应用的缓存目录
        let appSupportURL = home.appendingPathComponent("Library/Application Support")
        if let apps = try? fileManager.contentsOfDirectory(at: appSupportURL, includingPropertiesForKeys: nil) {
            for appURL in apps {
                let appName = appURL.lastPathComponent
                
                // ⚠️ 跳过已安装应用的缓存
                // if !isOrphanedAppSupport(dirName: appName, installedIds: installedAppBundleIds) {
                //    continue
                // }
                
                for cacheDirName in ["Cache", "Caches", "cache", "GPUCache", "Code Cache", "ShaderCache"] {
                    let cacheDir = appURL.appendingPathComponent(cacheDirName)
                    if fileManager.fileExists(atPath: cacheDir.path) {
                        let size = calculateSize(at: cacheDir)
                        if size > 50 * 1024 {
                            let fileItem = CleanerFileItem(
                                url: cacheDir,
                                name: "\(appName) \(cacheDirName)",
                                size: size,
                                groupId: "userCache"
                            )
                            addItem(fileItem, appName)
                        }
                    }
                }
            }
        }
        
        // 5. 扫描 ~/Library/Preferences (已卸载应用的 plist)
        // ⚠️ 安全改进：暂时禁用已卸载应用残留扫描，用户反馈会误删正常应用文件
        // let prefsURL = home.appendingPathComponent("Library/Preferences")
        // if let prefs = try? fileManager.contentsOfDirectory(at: prefsURL, includingPropertiesForKeys: nil) {
        //     for prefURL in prefs {
        //         if prefURL.pathExtension == "plist" {
        //             let bundleId = prefURL.deletingPathExtension().lastPathComponent
        //             if isOrphanedFile(bundleId: bundleId, installedIds: installedAppBundleIds) {
        //                 if let attrs = try? fileManager.attributesOfItem(atPath: prefURL.path),
        //                    let size = attrs[.size] as? Int64, size > 1024 {
        //                     items.append(CleanerFileItem(
        //                         url: prefURL,
        //                         name: "⚠️ \(formatAppName(bundleId)) 偏好设置 (已卸载)",
        //                         size: size,
        //                         groupId: "userCache"
        //                     ))
        //                 }
        //             }
        //         }
        //     }
        // }
        
        // 6. 已移除 ~/Library/Cookies 扫描 - 删除会导致所有网站登录状态丢失
        // 如需清理 Cookies，请使用隐私清理模块并明确确认
        
        // WebKit and HTTPStorages contain cookies and persistent website data.
        // Never treat their roots as automatically disposable cache.

        // 9. 扫描 ~/Library/Logs 作为用户缓存的一部分
        let logsURL = home.appendingPathComponent("Library/Logs")
        if let logs = try? fileManager.contentsOfDirectory(at: logsURL, includingPropertiesForKeys: nil) {
            for logURL in logs {
                let size = calculateSize(at: logURL)
                if size > 50 * 1024 {
                    let fileItem = CleanerFileItem(
                        url: logURL,
                        name: "\(logURL.lastPathComponent) 日志",
                        size: size,
                        groupId: "userCache"
                    )
                    
                    // 尝试将日志归类到应用
                    let logName = logURL.lastPathComponent
                    // 移除可能的后缀如 .log, -helper 等尝试匹配
                    let possibleAppId = logName.replacingOccurrences(of: ".log", with: "")
                    addItem(fileItem, possibleAppId)
                }
            }
        }
        
        // Trash is managed by its dedicated module.
        
        // 11. 开发者工具缓存 (IDEA, VSCode, Cursor, Navicat 等)
        let developerPaths: [(name: String, path: String, appIdentifier: String)] = [
            // JetBrains / IDEA
            ("JetBrains Caches", "Library/Caches/JetBrains", "jetbrains"),
            ("JetBrains Logs", "Library/Logs/JetBrains", "jetbrains"),
            
            // VSCode
            ("VSCode Caches", "Library/Caches/com.microsoft.VSCode", "com.microsoft.VSCode"),
            ("VSCode CachedData", "Library/Application Support/Code/CachedData", "com.microsoft.VSCode"),
            
            // Cursor
            ("Cursor Caches", "Library/Caches/com.tull.cursor", "com.tull.cursor"),
            ("Cursor Caches", "Library/Caches/Cursor", "com.tull.cursor"),
            ("Cursor CachedData", "Library/Application Support/Cursor/CachedData", "com.tull.cursor"),
            
            // Navicat
            ("Navicat Caches", "Library/Caches/com.prect.Navicat", "com.prect.Navicat"),
            ("Navicat Premium Caches", "Library/Caches/com.prect.NavicatPremium", "com.prect.NavicatPremium"),
            
            // Antigravity & Kiro (用户指定)
            ("Antigravity Caches", "Library/Caches/antigravity", "antigravity"),
            ("Kiro Caches", "Library/Caches/kiro", "kiro")
        ]
        
        for devApp in developerPaths {
            let url = home.appendingPathComponent(devApp.path)
            if fileManager.fileExists(atPath: url.path) {
                let size = calculateSize(at: url)
                if size > 1024 * 1024 { // > 1MB 才显示
                    let fileItem = CleanerFileItem(
                        url: url,
                        name: "🛠️ \(devApp.name)",
                        size: size,
                        groupId: "userCache"
                    )
                    addItem(fileItem, devApp.appIdentifier)
                }
            }
        }
        
        // 9. 更新服务状态
        let finalGroups = Array(groupsMap.values).sorted { $0.totalSize > $1.totalSize }
        await MainActor.run {
            self.appCacheGroups = finalGroups
        }
        
        return items.sorted { $0.size > $1.size }
    }
    
    // MARK: - 废纸篓扫描
    // MARK: - 辅助方法：获取已安装应用信息（改进版）
    /// 返回 (bundleIds, appNames, appMap) 元组，用于更精确的匹配和展示
    private func getInstalledAppInfo() -> (bundleIds: Set<String>, appNames: Set<String>, appMap: [String: (name: String, path: URL, bundleId: String?)]) {
        var bundleIds = Set<String>()
        var appNames = Set<String>()
        var appMap: [String: (name: String, path: URL, bundleId: String?)] = [:]
        
        let home = fileManager.homeDirectoryForCurrentUser
        
        // 1. 扫描标准应用目录
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            home.appendingPathComponent("Applications").path
        ]
        
        for appDir in appDirs {
            if let apps = try? fileManager.contentsOfDirectory(atPath: appDir) {
                for app in apps where app.hasSuffix(".app") {
                    let appPathString = (appDir as NSString).appendingPathComponent(app)
                    let appURL = URL(fileURLWithPath: appPathString)
                    let plistPath = appPathString + "/Contents/Info.plist"
                    
                    let appName = (app as NSString).deletingPathExtension
                    let lowerAppName = appName.lowercased()
                    appNames.insert(lowerAppName)
                    
                    if let plist = NSDictionary(contentsOfFile: plistPath),
                       let bundleId = plist["CFBundleIdentifier"] as? String {
                        let lowerBundleId = bundleId.lowercased()
                        bundleIds.insert(bundleId)
                        bundleIds.insert(lowerBundleId)
                        
                        let info = (name: appName, path: appURL, bundleId: bundleId)
                        appMap[lowerBundleId] = info
                        appMap[lowerAppName] = info
                        
                        // 提取 Bundle ID 的最后一个组件作为备用匹配
                        if let lastComponent = bundleId.components(separatedBy: ".").last {
                            let lowerLast = lastComponent.lowercased()
                            appNames.insert(lowerLast)
                            if appMap[lowerLast] == nil {
                                appMap[lowerLast] = info
                            }
                        }
                    } else {
                        // 如果没有 Bundle ID，也根据名称记录
                        let info = (name: appName, path: appURL, bundleId: nil as String?)
                        appMap[lowerAppName] = info
                    }
                }
            }
        }
        
        // 2. 扫描 Homebrew Cask 安装的应用
        let homebrewPaths = [
            "/opt/homebrew/Caskroom",
            "/usr/local/Caskroom"
        ]
        
        for caskPath in homebrewPaths {
            if let casks = try? fileManager.contentsOfDirectory(atPath: caskPath) {
                for cask in casks {
                    let lowerCask = cask.lowercased()
                    appNames.insert(lowerCask)
                    // 如果 Cask 下有应用，尝试获取其实际信息（简化处理：仅记录名称）
                }
            }
        }
        
        // 3. 添加正在运行的应用（最重要的安全检查）
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            if let bundleId = app.bundleIdentifier {
                let lowerBundleId = bundleId.lowercased()
                bundleIds.insert(bundleId)
                bundleIds.insert(lowerBundleId)
                
                if let name = app.localizedName {
                    let lowerName = name.lowercased()
                    appNames.insert(lowerName)
                    if appMap[lowerBundleId] == nil && appMap[lowerName] == nil {
                        // 尝试为运行的应用查找路径
                        if let appURL = app.bundleURL {
                            appMap[lowerBundleId] = (name: name, path: appURL, bundleId: bundleId)
                        }
                    }
                }
            }
        }
        
        // 4. 添加系统关键服务的白名单
        let systemSafelist = [
            // Apple 服务
            "com.apple", "apple", "icloud", "cloudkit", "safari", "mail", "messages",
            "photos", "music", "podcasts", "news", "tv", "books", "maps", "notes",
            "reminders", "calendar", "contacts", "facetime", "preview", "quicktime",
            // 系统组件
            "finder", "dock", "spotlight", "siri", "systemuiserver", "loginwindow",
            "windowserver", "coreaudio", "coremedia", "coreservices",
            // 常见第三方应用组件
            "google", "chrome", "microsoft", "edge", "firefox", "mozilla",
            "adobe", "dropbox", "slack", "discord", "zoom", "telegram", "whatsapp",
            "wechat", "qq", "tencent", "alibaba", "jetbrains", "vscode", "visual studio"
        ]
        
        for safe in systemSafelist {
            appNames.insert(safe)
        }
        
        return (bundleIds, appNames, appMap)
    }
    
    // 保留旧方法以兼容现有调用
    private func getInstalledAppBundleIds() -> Set<String> {
        return getInstalledAppInfo().bundleIds
    }
    
    // MARK: - 辅助方法：检测是否为已卸载应用的残留（改进版）
    private func isOrphanedFile(bundleId: String, installedIds: Set<String>) -> Bool {
        let lowerBundleId = bundleId.lowercased()
        
        // 0. 跳过以 . 开头的系统隐藏偏好设置文件
        // 这些文件存储全局系统设置，如 .GlobalPreferences.plist（自然滚动、语言等）
        if bundleId.hasPrefix(".") { return false }
        
        // 1. 跳过所有 Apple 系统服务
        if lowerBundleId.hasPrefix("com.apple.") { return false }
        if lowerBundleId.hasPrefix("apple") { return false }
        
        // 2. 扩展的系统/非应用目录白名单
        let systemDirs = [
            "cloudkit", "geoservices", "familycircle", "knowledge", "metadata",
            "tmp", "t", "caches", "cache", "logs", "preferences", "temp",
            "cookies", "webkit", "httpstorages", "containers", "group containers",
            "databases", "keychains", "accounts", "mail", "calendars", "contacts"
        ]
        if systemDirs.contains(lowerBundleId) { return false }
        
        // 3. 获取完整的应用信息
        let appInfo = getInstalledAppInfo()
        
        // 4. 检查 Bundle ID 是否匹配已安装应用
        if appInfo.bundleIds.contains(bundleId) || appInfo.bundleIds.contains(lowerBundleId) {
            return false
        }
        
        // 5. 检查应用名称是否匹配（模糊匹配）
        for appName in appInfo.appNames {
            if lowerBundleId.contains(appName) || appName.contains(lowerBundleId) {
                return false
            }
        }
        
        // 6. 检查 Bundle ID 各组件是否匹配应用名称
        let components = bundleId.components(separatedBy: ".")
        for component in components where component.count > 3 {
            if appInfo.appNames.contains(component.lowercased()) {
                return false
            }
        }
        
        // 所有检查都通过，才认为是孤立文件
        return true
    }
    
    private func isOrphanedAppSupport(dirName: String, installedIds: Set<String>) -> Bool {
        let lowerDirName = dirName.lowercased()
        
        // 1. 扩展的系统目录白名单（更全面）
        let systemSafelist = [
            // Apple 系统服务
            "apple", "crashreporter", "addressbook", "callhistorydb", "dock", "icloud",
            "knowledge", "mobilesync", "systemuiserver", "finder", "spotlight",
            "assistant", "siri", "icdd", "accounts", "bluetooth", "audio",
            // 系统框架和服务
            "coreservices", "coremedia", "coreaudio", "webkit", "cfnetwork",
            "networkservices", "securityagent", "syncservices", "ubiquity",
            // 常见应用名称变体
            "google", "chrome", "microsoft", "firefox", "mozilla", "safari",
            "adobe", "dropbox", "slack", "discord", "zoom", "telegram", "whatsapp",
            "wechat", "qq", "tencent", "alibaba", "jetbrains", "visual studio",
            // 开发工具
            "xcode", "simulator", "instruments", "compilers", "llvm", "clang",
            "homebrew", "brew", "npm", "yarn", "node", "python", "ruby", "java",
            // 媒体和音频
            "avid", "ableton", "logic", "garageband", "final cut", "motion",
            // 安全和系统工具
            "1password", "lastpass", "keychain", "security", "firewall",
            // 特殊处理
            "antigravity", "macoptimizer"
        ]
        
        for safe in systemSafelist {
            if lowerDirName.localizedCaseInsensitiveContains(safe) {
                return false
            }
        }
        
        // 2. 获取完整应用信息
        let appInfo = getInstalledAppInfo()
        
        // 3. 检查目录名是否与已安装应用匹配
        // 检查 Bundle ID
        for bundleId in appInfo.bundleIds {
            let lowerBundleId = bundleId.lowercased()
            
            // 完整匹配
            if lowerDirName == lowerBundleId {
                return false
            }
            
            // Bundle ID 包含目录名（例如 com.google.Chrome 包含 google）
            if lowerBundleId.contains(lowerDirName) && lowerDirName.count > 3 {
                return false
            }
            
            // 目录名包含 Bundle ID 组件
            let components = bundleId.components(separatedBy: ".")
            for component in components where component.count > 3 {
                if lowerDirName.contains(component.lowercased()) {
                    return false
                }
            }
        }
        
        // 4. 检查应用名称
        for appName in appInfo.appNames {
            // 双向模糊匹配
            if lowerDirName.contains(appName) || appName.contains(lowerDirName) {
                return false
            }
            
            // 处理空格分隔的应用名（例如 "Visual Studio Code"）
            let dirWords = lowerDirName.components(separatedBy: CharacterSet.alphanumerics.inverted)
            let appWords = appName.components(separatedBy: CharacterSet.alphanumerics.inverted)
            
            // 如果有多个共同词汇，认为匹配
            let commonWords = Set(dirWords).intersection(Set(appWords)).filter { $0.count > 2 }
            if commonWords.count >= 2 {
                return false
            }
        }
        
        // 5. 额外安全检查：如果目录看起来是某种框架或插件，不要删除
        let frameworkPatterns = ["framework", "plugin", "extension", "helper", "service", "daemon", "agent", "bundle"]
        for pattern in frameworkPatterns {
            if lowerDirName.contains(pattern) {
                return false
            }
        }
        
        // 所有检查都通过，才认为是孤立目录
        return true
    }
    
    private func formatAppName(_ bundleId: String) -> String {
        return bundleId
            .replacingOccurrences(of: "com.apple.", with: "Apple ")
            .replacingOccurrences(of: "com.tencent.", with: "腾讯 ")
            .replacingOccurrences(of: "com.google.", with: "Google ")
            .replacingOccurrences(of: "com.microsoft.", with: "Microsoft ")
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: "io.", with: "")
            .replacingOccurrences(of: "org.", with: "")
    }
    
    // MARK: - 语言文件扫描
    // MARK: - 语言文件扫描
    // scanLanguageFiles 已删除 - 删除应用的 .lproj 文件会破坏代码签名
    
    // MARK: - 系统日志扫描
    private func scanSystemLogs() async -> [CleanerFileItem] {
        var items: [CleanerFileItem] = []
        let paths = [
            "/Library/Logs",
            "/private/var/log"
        ]
        
        for pathStr in paths {
            let url = URL(fileURLWithPath: pathStr)
            guard fileManager.fileExists(atPath: url.path) else { continue }
            
            // 使用 directoryEnumerator 进行递归扫描，跳过隐藏文件
            if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                if shouldStopScanning || Task.isCancelled { break }
                    let ext = fileURL.pathExtension.lowercased()
                    // 扩展检查范围
                    if ["log", "txt", "crash", "diag", "out", "err", "panic"].contains(ext) || fileURL.lastPathComponent.contains("log") {
                        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                           let size = values.fileSize, size > 0 {
                            // 确保不是目录
                            if let isDir = values.isDirectory, !isDir {
                                items.append(CleanerFileItem(
                                    url: fileURL,
                                    name: fileURL.lastPathComponent,
                                    size: Int64(size),
                                    groupId: "systemLogs"
                                ))
                            }
                        }
                    }
                }
            }
        }
        
        return items.sorted { $0.size > $1.size }
    }
    
    // MARK: - 用户日志扫描
    private func scanUserLogs() async -> [CleanerFileItem] {
        var items: [CleanerFileItem] = []
        let home = fileManager.homeDirectoryForCurrentUser
        
        // 1. 标准日志目录 ~/Library/Logs
        let logsURL = home.appendingPathComponent("Library/Logs")
        
        if fileManager.fileExists(atPath: logsURL.path) {
            if let enumerator = fileManager.enumerator(at: logsURL, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                if shouldStopScanning || Task.isCancelled { break }
                    if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                       let isDir = values.isDirectory, !isDir,
                       let size = values.fileSize, size > 0 {
                        // 简单检查是否看起来像日志文件（可选，但 userLogs 目录里一般都是日志）
                        items.append(CleanerFileItem(
                            url: fileURL,
                            name: fileURL.lastPathComponent,
                            size: Int64(size),
                            groupId: "userLogs"
                        ))
                    }
                }
            }
        }
        
        // 2. 扫描 ~/Library/Application Support 中的 .log 文件
        // 用户提到"应用参数日志文件"，通常隐藏在 App Support 中
        let appSupportURL = home.appendingPathComponent("Library/Application Support")
        if fileManager.fileExists(atPath: appSupportURL.path) {
             if let enumerator = fileManager.enumerator(at: appSupportURL, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                if shouldStopScanning || Task.isCancelled { break }
                    // 只关心 .log 文件，严格匹配扩展名防误删
                    if fileURL.pathExtension.lowercased() == "log" {
                        if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                           let isDir = values.isDirectory, !isDir,
                           let size = values.fileSize, size > 0 {
                            items.append(CleanerFileItem(
                                url: fileURL,
                                name: fileURL.lastPathComponent,
                                size: Int64(size),
                                groupId: "userLogs"
                            ))
                        }
                    }
                }
            }
        }
        
        return items.sorted { $0.size > $1.size }
    }
    
    // MARK: - 损坏的登录项扫描
    // scanBrokenLoginItems 已删除 - 不符合"只清理缓存"原则
    
    // MARK: - 扫描重复文件 - 多线程优化版
    func scanDuplicates() async {
        await withScanSession { await self.performScanDuplicates() }
    }

    private func performScanDuplicates() async {
        await MainActor.run {
            isScanning = true
            setProgress(0)
            duplicateGroups = []
            currentCategory = .duplicates
        }
        
        // 1. 并行扫描所有目录，按文件大小分组
        var sizeGroups: [Int64: [URL]] = [:]
        let sizeGroupsCollector = ScanResultCollector<(Int64, URL)>()
        
        await withTaskGroup(of: [(Int64, URL)].self) { group in
            for dir in scanDirectories {
                group.addTask {
                    await self.collectFilesBySize(in: dir)
                }
            }
            
            for await results in group {
                await sizeGroupsCollector.appendContents(of: results)
            }
        }
        
        // 构建大小分组
        let allSizeResults = await sizeGroupsCollector.getResults()
        for (size, url) in allSizeResults {
            if sizeGroups[size] == nil {
                sizeGroups[size] = []
            }
            sizeGroups[size]?.append(url)
        }
        
        let _ = allSizeResults.count
        
        // 2. 筛选出同大小的文件组（潜在重复）
        let potentialDuplicates = sizeGroups.filter { $0.value.count > 1 }
        let filesToHash = potentialDuplicates.flatMap { $0.value }
        
        await MainActor.run {
            setProgress(0.3)
            currentScanPath = "正在计算文件哈希..."
        }
        
        // 3. 并行计算 MD5 哈希
        var hashGroups: [String: [CleanerFileItem]] = [:]
        let hashResultsCollector = ScanResultCollector<(String, CleanerFileItem)>()
        
        let chunkSize = max(10, filesToHash.count / 8) // 分成最多 8 个任务
        let chunks = stride(from: 0, to: filesToHash.count, by: chunkSize).map {
            Array(filesToHash[$0..<min($0 + chunkSize, filesToHash.count)])
        }
        
        let progressTracker = ScanProgressTracker()
        await progressTracker.setTotalTasks(chunks.count)
        
        await withTaskGroup(of: [(String, CleanerFileItem)].self) { group in
            for chunk in chunks {
                group.addTask {
                    var results: [(String, CleanerFileItem)] = []
                    
                    for url in chunk {
                        if self.shouldStopScanning || Task.isCancelled { break }
                        if let hash = self.md5Hash(of: url),
                           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            let item = CleanerFileItem(
                                url: url,
                                name: url.lastPathComponent,
                                size: Int64(size),
                                groupId: hash
                            )
                            results.append((hash, item))
                        }
                    }
                    
                    return results
                }
            }
            
            // 收集哈希结果
            for await chunkResults in group {
                await hashResultsCollector.appendContents(of: chunkResults)
                await progressTracker.completeTask()
                
                let progress = await progressTracker.getProgress()
                await MainActor.run {
                    self.setProgress(0.3 + progress * 0.7)
                }
            }
        }
        
        // 构建哈希分组
        let allHashResults = await hashResultsCollector.getResults()
        for (hash, item) in allHashResults {
            if hashGroups[hash] == nil {
                hashGroups[hash] = []
            }
            hashGroups[hash]?.append(item)
        }
        
        // 4. 筛选真正的重复组
        let groups = hashGroups.compactMap { (hash, files) -> DuplicateGroup? in
            guard files.count > 1 else { return nil }
            return DuplicateGroup(hash: hash, files: files)
        }.sorted { $0.wastedSize > $1.wastedSize }
        
        await MainActor.run {
            duplicateGroups = groups
            setProgress(1.0)
            currentScanPath = ""
        }
    }
    
    /// 并行收集目录中的文件及其大小
    private func collectFilesBySize(in directory: URL) async -> [(Int64, URL)] {
        var results: [(Int64, URL)] = []
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return results }
        
        var lastUpdate = Date.distantPast
        while let fileURL = enumerator.nextObject() as? URL {
            if shouldStopScanning || Task.isCancelled { break }
            if Date().timeIntervalSince(lastUpdate) >= 0.1 {
                await MainActor.run { self.currentScanPath = fileURL.path }
                lastUpdate = Date()
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDir = values.isDirectory, !isDir,
                  let size = values.fileSize, size > 1024 else { continue }
            
            results.append((Int64(size), fileURL))
        }
        
        return results
    }
    
    // MARK: - 扫描相似照片
    func scanSimilarPhotos() async {
        await withScanSession { await self.performScanSimilarPhotos() }
    }

    private func performScanSimilarPhotos() async {
        await MainActor.run {
            isScanning = true
            setProgress(0)
            similarPhotoGroups = []
            currentCategory = .similarPhotos
        }
        
        let picturesDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        var photos: [(url: URL, fingerprint: VNFeaturePrintObservation)] = []
        var processedCount = 0
        var totalCount = 0
        
        // 收集所有图片
        if let enumerator = fileManager.enumerator(at: picturesDir, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if shouldStopScanning || Task.isCancelled { break }
                let ext = fileURL.pathExtension.lowercased()
                if ["jpg", "jpeg", "png", "heic", "heif", "tiff"].contains(ext) {
                    totalCount += 1
                }
            }
        }
        
        // 计算图片特征
        if let enumerator = fileManager.enumerator(at: picturesDir, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if shouldStopScanning || Task.isCancelled { break }
                let ext = fileURL.pathExtension.lowercased()
                guard ["jpg", "jpeg", "png", "heic", "heif", "tiff"].contains(ext) else { continue }
                
                processedCount += 1
                await MainActor.run { [processedCount, totalCount] in
                    setProgress(Double(processedCount) / Double(max(totalCount, 1)))
                    currentScanPath = fileURL.path
                }
                
                if let fingerprint = await extractImageFingerprint(from: fileURL) {
                    photos.append((url: fileURL, fingerprint: fingerprint))
                }
            }
        }
        
        // 比较相似度
        var similarGroups: [String: [CleanerFileItem]] = [:]
        var matched: Set<URL> = []
        
        for i in 0..<photos.count {
            if shouldStopScanning || Task.isCancelled { break }
            guard !matched.contains(photos[i].url) else { continue }
            
            var groupFiles: [CleanerFileItem] = []
            let size1 = (try? photos[i].url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            groupFiles.append(CleanerFileItem(
                url: photos[i].url,
                name: photos[i].url.lastPathComponent,
                size: Int64(size1),
                groupId: photos[i].url.path
            ))
            
            for j in (i+1)..<photos.count {
                if shouldStopScanning || Task.isCancelled { break }
                guard !matched.contains(photos[j].url) else { continue }
                
                var distance: Float = 0
                try? photos[i].fingerprint.computeDistance(&distance, to: photos[j].fingerprint)
                
                // 距离越小越相似，阈值 0.5 表示约 50% 相似
                if distance < 0.4 {
                    matched.insert(photos[j].url)
                    let size2 = (try? photos[j].url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    groupFiles.append(CleanerFileItem(
                        url: photos[j].url,
                        name: photos[j].url.lastPathComponent,
                        size: Int64(size2),
                        groupId: photos[i].url.path
                    ))
                }
            }
            
            if groupFiles.count > 1 {
                matched.insert(photos[i].url)
                similarGroups[photos[i].url.path] = groupFiles
            }
        }
        
        let groups = similarGroups.map { (key, files) in
            DuplicateGroup(hash: key, files: files)
        }.sorted { $0.totalSize > $1.totalSize }
        
        await MainActor.run {
            similarPhotoGroups = groups
            setProgress(1.0)
            currentScanPath = ""
        }
    }
    
    // MARK: - 扫描多语言文件 - 多线程优化版
    func scanLocalizations() async {
        await withScanSession { await self.performScanLocalizations() }
    }

    private func performScanLocalizations() async {
        await MainActor.run {
            isScanning = true
            scanProgress = 0
            localizationFiles = []
            currentCategory = .localizations
        }
        
        let applicationsDir = URL(fileURLWithPath: "/Applications")
        let userAppsDir = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        
        // 收集所有应用
        var allApps: [URL] = []
        for dir in [applicationsDir, userAppsDir] {
            if let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                allApps.append(contentsOf: contents.filter { $0.pathExtension == "app" })
            }
        }
        
        let totalApps = allApps.count
        let progressTracker = ScanProgressTracker()
        await progressTracker.setTotalTasks(totalApps)
        
        // 并行扫描所有应用
        let collector = ScanResultCollector<CleanerFileItem>()
        
        await withTaskGroup(of: [CleanerFileItem].self) { group in
            for app in allApps {
                group.addTask {
                    await self.scanAppLocalizations(app)
                }
            }
            
            for await appItems in group {
                await collector.appendContents(of: appItems)
                await progressTracker.completeTask()
                
                let progress = await progressTracker.getProgress()
                await MainActor.run {
                    self.scanProgress = progress
                }
            }
        }
        
        let items = await collector.getResults()
        
        await MainActor.run {
            localizationFiles = items.sorted { $0.size > $1.size }
            currentScanPath = ""
        }
    }
    
    /// 扫描单个应用的多语言文件
    private func scanAppLocalizations(_ app: URL) async -> [CleanerFileItem] {
        var items: [CleanerFileItem] = []
        
        let resourcesDir = app.appendingPathComponent("Contents/Resources")
        guard let resources = try? fileManager.contentsOfDirectory(at: resourcesDir, includingPropertiesForKeys: nil) else {
            return items
        }
        
        for resource in resources {
            let name = resource.lastPathComponent
            guard name.hasSuffix(".lproj"), !keepLocalizations.contains(name) else { continue }
            
            let size = calculateSize(at: resource)
            let item = CleanerFileItem(
                url: resource,
                name: "\(app.deletingPathExtension().lastPathComponent) - \(name)",
                size: size,
                groupId: app.lastPathComponent
            )
            items.append(item)
        }
        
        return items
    }
    
    // MARK: - 扫描大文件 - 多线程优化版
    func scanLargeFiles(minSize: Int64 = 100 * 1024 * 1024) async {
        await withScanSession { await self.performScanLargeFiles(minSize: minSize) }
    }

    private func performScanLargeFiles(minSize: Int64) async { // 默认 100MB
        await MainActor.run {
            isScanning = true
            setProgress(0)
            largeFiles = []
            currentCategory = .largeFiles
        }
        
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let applicationsDir = URL(fileURLWithPath: "/Applications")
        let sharedDir = URL(fileURLWithPath: "/Users/Shared")
        
        // 获取所有可访问的卷 (排除系统引导卷，以免重复扫描)
        var scanTargets: [URL] = [applicationsDir, sharedDir]
        
        // 1. 获取家目录下所有二级目录
        var homeRootLargeFiles: [CleanerFileItem] = []
        if let homeContents = try? fileManager.contentsOfDirectory(at: homeDir, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
            for url in homeContents {
                let name = url.lastPathComponent
                if name == "Library" { continue }
                
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]) else { continue }
                
                if values.isDirectory == true {
                    scanTargets.append(url)
                } else if let size = values.fileSize, Int64(size) >= minSize {
                    homeRootLargeFiles.append(CleanerFileItem(url: url, name: url.lastPathComponent, size: Int64(size), groupId: "large"))
                }
            }
        }
        
        // 2. 获取其他卷 (如外置硬盘)
        if let volumes = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for vol in volumes {
                let name = vol.lastPathComponent
                // 排除一些系统保留或特殊的挂载点 (通常 Macintosh HD 是指向根目录的连接或挂载)
                if name == "Macintosh HD" || name == "Preboot" || name == "Recovery" || name == "VM" {
                    continue
                }
                scanTargets.append(vol)
            }
        }
        
        // 并行扫描所有目录
        let collector = ScanResultCollector<CleanerFileItem>()
        // 预存家目录根文件
        for file in homeRootLargeFiles {
            await collector.append(file)
        }
        
        let progressTracker = ScanProgressTracker()
        await progressTracker.setTotalTasks(scanTargets.count)
        
        await withTaskGroup(of: [CleanerFileItem].self) { group in
            for dirURL in scanTargets {
                group.addTask {
                    await self.scanDirectoryForLargeFiles(dirURL, minSize: minSize)
                }
            }
            
            for await dirItems in group {
                await collector.appendContents(of: dirItems)
                await progressTracker.completeTask()
                
                let progress = await progressTracker.getProgress()
                await MainActor.run {
                    self.setProgress(progress)
                }
            }
        }
        
        let items = await collector.getResults()
        
        await MainActor.run {
            largeFiles = items.sorted { $0.size > $1.size }
            currentScanPath = ""
        }
    }
    
    /// 扫描目录中的大文件
    private func scanDirectoryForLargeFiles(_ directory: URL, minSize: Int64) async -> [CleanerFileItem] {
        var items: [CleanerFileItem] = []
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return items }
        
        while let fileURL = enumerator.nextObject() as? URL {
            if shouldStopScanning || Task.isCancelled { break }
            await self.publishScanPath(fileURL.path)
            // 跳过 Library 等系统目录
            if fileURL.path.contains("/Library/") || fileURL.path.contains("/.git/") {
                continue
            }
            
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  let isDir = values.isDirectory, !isDir,
                  let size = values.fileSize, Int64(size) >= minSize else { continue }
            
            // ⚠️ 安全改进：大文件默认不勾选，需要用户手动确认才清理
            let item = CleanerFileItem(
                url: fileURL,
                name: fileURL.lastPathComponent,
                size: Int64(size),
                groupId: "large",
                isSelected: false  // 默认不选中
            )
            items.append(item)
        }
        
        return items
    }
    
    // MARK: - 扫描性能优化 (内存占用过高)
    func scanPerformanceApps() async {
        await withScanSession { await self.performScanPerformanceApps() }
    }

    private func performScanPerformanceApps() async {
        await MainActor.run {
            currentCategory = .performanceApps
            currentScanPath = "Preparing performance scan..."
            // scanProgress = 0 // Removed to respect range
        }
        
        // 1. 获取所有进程内存使用情况 (Map: PID -> MemoryBytes)
        let memoryMap = await fetchProcessMemoryMap()
        
        // 2. 获取运行中的应用
        let apps = NSWorkspace.shared.runningApplications
        var highMemApps: [PerformanceAppItem] = []
        let highMemLimit: Int64 = 1 * 1024 * 1024 * 1024 // 1GB
        
        // 3. 遍历并显示进度
        for app in apps {
            // 过滤系统后台进程
            guard app.activationPolicy == .regular else { continue }
            
            // 实时更新扫描路径 (UI 显示正在扫描的应用名称)
            let appName = app.localizedName ?? "Unknown"
            await self.publishScanPath("Scanning \(appName)...")
            
            // 检查内存
            if let memory = memoryMap[app.processIdentifier] {
                if memory > highMemLimit {
                    let item = PerformanceAppItem(
                        name: appName,
                        icon: app.icon ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!,
                        memoryUsage: memory,
                        bundleId: app.bundleIdentifier,
                        runningApp: app
                    )
                    highMemApps.append(item)
                }
            }
            
            // 稍微让出时间片更新UI (可选，因为循环可能很快)
            await Task.yield()
        }
        
        let finalApps = highMemApps
        await MainActor.run {
            self.performanceApps = finalApps
            // 默认选中所有
            for i in performanceApps.indices {
                performanceApps[i].isSelected = true
            }
            currentScanPath = ""
        }
    }
    
    // MARK: - 删除选中文件
    @MainActor
    func deleteSelectedFiles(from category: CleanerCategory) async -> (success: Int, failed: Int, size: Int64) {
        guard !isCleaning && !isScanning else { return (0, 0, 0) }
        let candidates: [CleanerFileItem]
        switch category {
        case .duplicates: candidates = duplicateGroups.flatMap { Array($0.files.dropFirst()) }
        case .similarPhotos: candidates = similarPhotoGroups.flatMap { Array($0.files.dropFirst()) }
        case .largeFiles: candidates = largeFiles
        default: return (0, 0, 0)
        }
        isCleaning = true
        cleaningWasStopped = false
        setCleaningCancelled(false)
        let before = CleanupDiskSnapshot.capture()
        defer {
            isCleaning = false
            observedDiskSpaceChange = CleanupDiskSnapshot.capture()?.change(since: before)
        }
        var completed = Set<String>()
        var failed = 0
        var size: Int64 = 0
        for file in await Self.uniqueFilesForCleanup(candidates.filter(\.isSelected)) {
            if cleaningWasStopped || Task.isCancelled { break }
            if await deleteCleanupFile(file, bypassProtection: category == .largeFiles) {
                completed.insert(file.url.standardizedFileURL.resolvingSymlinksInPath().path)
                size += file.size
            } else { failed += 1 }
        }
        removeCleanedFiles(completed)
        totalMovedToTrashSize += size
        totalCleanedSize += size
        return (completed.count, failed, size)
    }

    // MARK: - 辅助方法
    
    private func md5Hash(of url: URL) -> String? {
        FileHashing.md5(at: url) { self.shouldStopScanning || Task.isCancelled }
    }
    
    private func extractImageFingerprint(from url: URL) async -> VNFeaturePrintObservation? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
    }
    
    func calculateSize(at url: URL) -> Int64 {
        // Managed runtimes and installation archives must never be swallowed
        // by an automatically selected parent cache directory.
        guard !InstallationResidueScanner.excludesGenericCleanup(url) else { return 0 }
        return CleanupFileSystem.logicalSize(at: url, shouldCancel: { self.shouldStopScanning || Task.isCancelled })
    }

    // MARK: - 统计
    
    func selectedCount(for category: CleanerCategory) -> Int {
        switch category {
        case .duplicates:
            return duplicateGroups.flatMap { $0.files }.filter { $0.isSelected }.count
        case .similarPhotos:
            return similarPhotoGroups.flatMap { $0.files }.filter { $0.isSelected }.count
        case .localizations:
            return localizationFiles.filter { $0.isSelected }.count
        case .largeFiles:
            return largeFiles.filter { $0.isSelected }.count
        case .systemJunk, .systemCache, .oldUpdates, .userCache, .trash, .systemLogs, .userLogs:
            return countFor(category: category)
        case .virus:
            return virusThreats.count
        case .appUpdates:
            return hasAppUpdates ? 1 : 0
        case .startupItems:
            return startupItems.count
        case .performanceApps:
            return performanceApps.filter { $0.isSelected }.count
        }
    }
    
    func selectedSize(for category: CleanerCategory) -> Int64 {
        switch category {
        case .duplicates:
            return duplicateGroups.flatMap { $0.files }.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        case .similarPhotos:
            return similarPhotoGroups.flatMap { $0.files }.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        case .localizations:
            return localizationFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        case .largeFiles:
            return largeFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        case .virus:
            return virusThreats.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        case .performanceApps:
            return performanceApps.filter { $0.isSelected }.reduce(0) { $0 + $1.memoryUsage }
        case .systemJunk, .systemCache, .oldUpdates, .userCache, .trash, .systemLogs, .userLogs, .appUpdates, .startupItems:
            return sizeFor(category: category)
        }
    }
    
    func totalWastedSize() -> Int64 {
        let duplicateWaste = duplicateGroups.reduce(0) { $0 + $1.wastedSize }
        let photoWaste = similarPhotoGroups.reduce(0) { $0 + $1.wastedSize }
        let locWaste = localizationFiles.reduce(0) { $0 + $1.size }
        return duplicateWaste + photoWaste + locWaste
    }
    
    // MARK: - 重置所有扫描结果
    @MainActor
    func resetAll() {
        guard activeScanID == nil && !isCleaning else {
            stopScanning()
            stopCleaning()
            return
        }
        beginJunkUpdates()
        defer { endJunkUpdates() }
        userCacheFiles = []
        systemCacheFiles = []
        oldUpdateFiles = []
        systemLogFiles = []
        userLogFiles = []
        duplicateGroups = []
        similarPhotoGroups = []
        localizationFiles = []
        largeFiles = []
        trashFiles = []
        totalMovedToTrashSize = 0
        totalCleanedSize = 0
        observedDiskSpaceChange = nil
        scanProgress = 0
        currentScanPath = ""
        
        // 新增重置
        appCacheGroups = []
        virusThreats = []
        startupItems = []
        performanceApps = []
        hasAppUpdates = false
    }
    
    // MARK: - 一键扫描所有
    @MainActor
    func scanAll() async {
        await withScanSession { await self.performScanAll() }
    }

    @MainActor
    private func performScanAll() async {
        // 重置停止标志和已扫描分类
        await MainActor.run { 
            scannedCategories = []
            scanProgress = 0.0
            isScanning = true
            isCleaning = false
            totalCleanedSize = 0
        }
        
        // --- 1. 系统垃圾 (仅缓存和日志) ---
        await MainActor.run { 
            currentCategory = .systemJunk
            currentScanPath = "Scanning for system junk..."
            progressRange = (0.0, 0.125)
        }
        await scanSystemJunk()
        
        await MainActor.run { _ = scannedCategories.insert(.systemJunk); scanProgress = 0.125 }
        if shouldStopScanning || Task.isCancelled { return }
        
        // --- 2. 重复文件 ---
        await MainActor.run { 
            currentCategory = .duplicates
            currentScanPath = "Searching for duplicates..."
            progressRange = (0.125, 0.25)
        }
        await scanDuplicates()
        await MainActor.run { _ = scannedCategories.insert(.duplicates); scanProgress = 0.25 }
        if shouldStopScanning || Task.isCancelled { return }
        
        // --- 3. 相似照片 ---
        await MainActor.run { 
            currentCategory = .similarPhotos
            currentScanPath = "Finding similar photos..."
            progressRange = (0.25, 0.375)
        }
        await scanSimilarPhotos()
        await MainActor.run { _ = scannedCategories.insert(.similarPhotos); scanProgress = 0.375 }
        if shouldStopScanning || Task.isCancelled { return }
        
        // --- 4. 大文件 ---
        await MainActor.run { 
            currentCategory = .largeFiles
            currentScanPath = "Scanning for large files..."
            progressRange = (0.375, 0.5)
        }
        await scanLargeFiles()
        await MainActor.run { _ = scannedCategories.insert(.largeFiles); scanProgress = 0.5 }
        if shouldStopScanning || Task.isCancelled { return }
        
        // --- 5. 病毒扫描 ---
        await MainActor.run { 
            currentCategory = .virus
            currentScanPath = "Scanning for threats..."
            progressRange = (0.5, 0.625)
            // Malware scanner doesn't report progress yet, so it bars 0.5-0.625
        }
        await malwareScanner.scan(shouldCancel: { self.shouldStopScanning || Task.isCancelled })
        await MainActor.run { 
            self.virusThreats = self.malwareScanner.threats
            _ = scannedCategories.insert(.virus)
            scanProgress = 0.625
        }
        if shouldStopScanning || Task.isCancelled { return }
        
        // --- 6. 启动项扫描 ---
        await MainActor.run { 
            currentCategory = .startupItems
            currentScanPath = "Scanning startup items..."
            progressRange = (0.625, 0.75)
        }
        await systemOptimizer.scanLaunchAgents()
        await MainActor.run { 
            self.startupItems = self.systemOptimizer.launchAgents.filter { $0.isEnabled }
            _ = scannedCategories.insert(.startupItems)
            scanProgress = 0.75
        }
        if shouldStopScanning || Task.isCancelled { return }
        
        // --- 7. 性能优化 (查找高内存应用) ---
        await MainActor.run { 
             currentCategory = .performanceApps 
             progressRange = (0.75, 0.875)
        }
        await scanPerformanceApps()
        await MainActor.run {
            _ = scannedCategories.insert(.performanceApps)
            scanProgress = 0.875
        }
        if shouldStopScanning || Task.isCancelled { return }
        
        // --- 8. 应用更新检查 ---
        await MainActor.run { 
            currentCategory = .appUpdates
            currentScanPath = "Checking for updates..."
            progressRange = (0.875, 1.0)
        }
        await updateChecker.checkForUpdates()
        await MainActor.run { 
            self.hasAppUpdates = self.updateChecker.hasUpdate
            _ = scannedCategories.insert(.appUpdates)
            scanProgress = 1.0 // Ensure finish
            progressRange = (0.0, 1.0) // Reset range
        }
        if shouldStopScanning || Task.isCancelled { return }

        
        // 扫描结束
        await MainActor.run {
            isScanning = false
            currentScanPath = ""
        }
    }
    
    @Published var isCleaning = false
    @Published var cleaningDescription: String = ""
    @Published var cleaningCurrentCategory: CleanerCategory? = nil
    @Published var cleanedCategories: Set<CleanerCategory> = []
    @Published private(set) var cleaningWasStopped = false

    @MainActor
    func stopCleaning() {
        guard isCleaning else { return }
        cleaningWasStopped = true
        setCleaningCancelled(true)
        malwareScanner.stopRemoval()
    }

    @MainActor
    func cleanAll() async -> (success: Int, failed: Int, size: Int64, failedFiles: [CleanerFileItem]) {
        guard !isCleaning && !isScanning else { return (0, 0, 0, []) }
        isCleaning = true
        cleaningWasStopped = false
        setCleaningCancelled(false)
        cleanedCategories = []
        lastFailedCleanupFiles = []
        totalCleanedSize = 0
        totalMovedToTrashSize = 0
        observedDiskSpaceChange = nil
        let diskBefore = CleanupDiskSnapshot.capture()
        totalResolvedThreats = 0
        totalOptimizedItems = 0
        defer {
            isCleaning = false
            cleaningCurrentCategory = nil
            cleaningDescription = ""
            observedDiskSpaceChange = CleanupDiskSnapshot.capture()?.change(since: diskBefore)
        }

        let junk = allJunkFiles + trashFiles
        let batches: [(CleanerCategory, [CleanerFileItem], Bool)] = [
            (.systemJunk, junk, false),
            (.duplicates, duplicateGroups.flatMap { Array($0.files.dropFirst()) }, false),
            (.similarPhotos, similarPhotoGroups.flatMap { Array($0.files.dropFirst()) }, false),
            (.largeFiles, largeFiles, true)
        ]
        let selectedCandidates = batches.flatMap { $0.1 }.filter(\.isSelected)
        let selectedRootFiles = await Self.uniqueFilesForCleanup(selectedCandidates)
        let selectedRoots = Set(selectedRootFiles.map { $0.url.standardizedFileURL.resolvingSymlinksInPath().path })
        var seen = Set<String>()
        var completed = Set<String>()
        var failedFiles: [CleanerFileItem] = []
        var success = 0
        var failed = 0
        var size: Int64 = 0
        for (category, files, bypassProtection) in batches {
            guard !cleaningWasStopped && !Task.isCancelled else { break }
            cleaningCurrentCategory = category
            for file in files where file.isSelected {
                guard !cleaningWasStopped && !Task.isCancelled else { break }
                let path = file.url.standardizedFileURL.resolvingSymlinksInPath().path
                guard selectedRoots.contains(file.url.standardizedFileURL.resolvingSymlinksInPath().path),
                      seen.insert(path).inserted else { continue }
                // A previously removed parent already accounts for this item.
                guard !completed.contains(where: { path.hasPrefix($0 + "/") }) else { continue }
                if await deleteCleanupFile(file, bypassProtection: bypassProtection) {
                    completed.insert(path)
                    success += 1
                    size += file.size
                    totalCleanedSize = size
                    totalMovedToTrashSize += file.size
                } else {
                    failed += 1
                    failedFiles.append(file)
                }
                await Task.yield()
            }
            if !cleaningWasStopped && !Task.isCancelled { cleanedCategories.insert(category) }
        }
        removeCleanedFiles(completed)

        if !cleaningWasStopped && !Task.isCancelled && !virusThreats.isEmpty {
            cleaningCurrentCategory = .virus
            let selected = virusThreats.filter(\.isSelected)
            malwareScanner.threats = virusThreats
            let result = await malwareScanner.removeThreats(shouldCancel: { self.isCleaningCancelled() || Task.isCancelled })
            let remaining = Set(malwareScanner.threats.map(\.path))
            let removedSize = selected.filter { !remaining.contains($0.path) }.reduce(Int64(0)) { $0 + $1.size }
            success += result.success
            failed += result.failed
            size += removedSize
            virusThreats = malwareScanner.threats
            totalResolvedThreats = result.success
            totalCleanedSize = size
            cleanedCategories.insert(.virus)
        }
        for item in startupItems where item.isSelected && item.isEnabled {
            guard !cleaningWasStopped && !Task.isCancelled else { break }
            cleaningCurrentCategory = .startupItems
            if await systemOptimizer.toggleAgent(item) {
                success += 1
                totalOptimizedItems += 1
            } else {
                failed += 1
            }
        }
        if !cleaningWasStopped && !Task.isCancelled && hasAppUpdates, let url = updateChecker.downloadURL {
            NSWorkspace.shared.open(url)
        }
        if Task.isCancelled { cleaningWasStopped = true }
        lastFailedCleanupFiles = failedFiles
        return (success, failed, size, failedFiles)
    }

    /// Retry uses the same safety checks and Trash behavior as the original run.
    @MainActor
    func retryFailedFiles(_ files: [CleanerFileItem]) async -> (success: Int, failed: Int, size: Int64) {
        guard !isCleaning && !isScanning else { return (0, files.count, 0) }
        isCleaning = true
        cleaningWasStopped = false
        setCleaningCancelled(false)
        let diskBefore = CleanupDiskSnapshot.capture()
        defer {
            isCleaning = false
            observedDiskSpaceChange = CleanupDiskSnapshot.capture()?.change(since: diskBefore)
        }
        var success = 0
        var size: Int64 = 0
        var seen = Set<String>()
        var completed = Set<String>()
        let selectedLargePaths = Set(largeFiles.filter(\.isSelected).map { $0.url.standardizedFileURL.resolvingSymlinksInPath().path })
        for file in await Self.uniqueFilesForCleanup(files) {
            guard !cleaningWasStopped && !Task.isCancelled else { break }
            let path = file.url.standardizedFileURL.resolvingSymlinksInPath().path
            guard seen.insert(path).inserted else { continue }
            if await deleteCleanupFile(file, bypassProtection: selectedLargePaths.contains(path)) {
                completed.insert(path)
                success += 1
                size += file.size
            }
            await Task.yield()
        }
        removeCleanedFiles(completed)
        totalCleanedSize += size
        totalMovedToTrashSize += size
        if Task.isCancelled { cleaningWasStopped = true }
        // Retain original failures which were never attempted after Stop as well
        // as attempts that failed. A successful parent accounts for descendants.
        var retainedPaths = Set<String>()
        lastFailedCleanupFiles = files.filter { file in
            let path = file.url.standardizedFileURL.resolvingSymlinksInPath().path
            let removed = completed.contains(path) || completed.contains { path.hasPrefix($0 + "/") }
            return !removed && retainedPaths.insert(path).inserted
        }
        return (success, lastFailedCleanupFiles.count, size)
    }

    private func deleteCleanupFile(_ file: CleanerFileItem, bypassProtection: Bool) async -> Bool {
        let path = file.url.standardizedFileURL.resolvingSymlinksInPath().path
        let trash = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").resolvingSymlinksInPath().path
        guard path != trash && !path.hasPrefix(trash + "/"),
              !file.url.pathComponents.contains(".Trashes") else { return false }
        if let candidate = file.installationResidue {
            guard file.url == candidate.url,
                  !isCleaningCancelled() && !Task.isCancelled,
                  await installationResidueValidator(candidate),
                  !isCleaningCancelled() && !Task.isCancelled else { return false }
        } else {
            guard deletionAllowed(file.url, bypassProtection && !file.isDirectory) else { return false }
        }
        return await cleanupFile(file.url, false)
    }

    @MainActor
    private func removeCleanedFiles(_ paths: Set<String>) {
        beginJunkUpdates()
        defer { endJunkUpdates() }
        let removed: (CleanerFileItem) -> Bool = { file in
            let path = file.url.standardizedFileURL.resolvingSymlinksInPath().path
            return paths.contains(path) || paths.contains { path.hasPrefix($0 + "/") }
        }
        userCacheFiles.removeAll(where: removed)
        systemCacheFiles.removeAll(where: removed)
        oldUpdateFiles.removeAll(where: removed)
        trashFiles.removeAll(where: removed)
        systemLogFiles.removeAll(where: removed)
        userLogFiles.removeAll(where: removed)
        largeFiles.removeAll(where: removed)
        for group in appCacheGroups { group.files.removeAll(where: removed) }
        appCacheGroups.removeAll { $0.files.isEmpty }
        duplicateGroups = duplicateGroups.compactMap { group in
            let files = group.files.filter { !removed($0) }
            return files.count > 1 ? DuplicateGroup(hash: group.hash, files: files) : nil
        }
        similarPhotoGroups = similarPhotoGroups.compactMap { group in
            let files = group.files.filter { !removed($0) }
            return files.count > 1 ? DuplicateGroup(hash: group.hash, files: files) : nil
        }
    }

    // MARK: - 全选/取消全选
    func selectAll(for category: CleanerCategory, selected: Bool) {
        switch category {
        case .duplicates:
            for i in 0..<duplicateGroups.count {
                for j in 0..<duplicateGroups[i].files.count {
                    duplicateGroups[i].files[j].isSelected = selected
                }
            }
        case .similarPhotos:
            for i in 0..<similarPhotoGroups.count {
                for j in 0..<similarPhotoGroups[i].files.count {
                    similarPhotoGroups[i].files[j].isSelected = selected
                }
            }
        case .localizations:
            for i in 0..<localizationFiles.count {
                localizationFiles[i].isSelected = selected
            }
        case .largeFiles:
            for i in 0..<largeFiles.count {
                largeFiles[i].isSelected = selected
            }
        case .systemJunk, .systemCache, .oldUpdates, .userCache, .trash, .systemLogs, .userLogs, .appUpdates:
            // 系统垃圾类别暂不支持单独选择
            break
        case .virus:
             // Virus threats don't have isSelected in DetectedThreat struct? 
             // Wait, DetectedThreat in MalwareScanner doesn't have isSelected? 
             // If not, we can't select. But usually generic CleanerFileItem has it.
             // Let's assume we can't or it's implicitly all.
             break
        case .startupItems:
             // Startup items usually don't have bulk select
             break
        case .performanceApps:
             for app in performanceApps {
                 app.isSelected = selected
             }
        }
    }
    
    // 总可清理大小（只计算已选中的文件）
    var totalCleanableSize: Int64 {
        // Use the same deduplicated cached accounting as the results page.
        let trashSize = trashFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        
        // 重复文件（只计算选中的文件）
        let dupSize = duplicateGroups.flatMap { $0.files }.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        
        // 相似照片（只计算选中的文件）
        let photoSize = similarPhotoGroups.flatMap { $0.files }.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        
        // 本地化文件
        let locSize = localizationFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        
        // 大文件
        let largeSize = largeFiles.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        
        // 病毒威胁
        let virusSize = virusThreats.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
        
        return systemJunkTotalSize + trashSize +
               dupSize + photoSize + locSize + largeSize + virusSize
    }
    
    // 获取所有选中的文件
    func getAllSelectedFiles() -> [CleanerFileItem] {
        var allFiles: [CleanerFileItem] = []
        
        // Simple lists
        allFiles.append(contentsOf: userCacheFiles.filter { $0.isSelected })
        allFiles.append(contentsOf: systemCacheFiles.filter { $0.isSelected })
        allFiles.append(contentsOf: oldUpdateFiles.filter { $0.isSelected })
        allFiles.append(contentsOf: trashFiles.filter { $0.isSelected })
        allFiles.append(contentsOf: systemLogFiles.filter { $0.isSelected })
        allFiles.append(contentsOf: userLogFiles.filter { $0.isSelected })
        
        // Groups
        for group in appCacheGroups {
            allFiles.append(contentsOf: group.files.filter { $0.isSelected })
        }
        
        // Duplicates & Photos
        allFiles.append(contentsOf: duplicateGroups.flatMap { $0.files }.filter { $0.isSelected })
        allFiles.append(contentsOf: similarPhotoGroups.flatMap { $0.files }.filter { $0.isSelected })
        
        // Others
        allFiles.append(contentsOf: localizationFiles.filter { $0.isSelected })
        allFiles.append(contentsOf: largeFiles.filter { $0.isSelected })
        
        return allFiles
    }
    
    func toggleStartupItem(_ item: LaunchItem) async {
        if await systemOptimizer.toggleAgent(item) {
            await MainActor.run {
                // Refresh local startup items list
                if let index = startupItems.firstIndex(where: { $0.id == item.id }) {
                    startupItems[index].isEnabled = item.isEnabled
                }
            }
        }
    }
    
    // MARK: - 检查运行中的应用
    func checkRunningApps(for files: [CleanerFileItem]) -> [(name: String, icon: NSImage?, bundleId: String)] {
        var runningApps: [(name: String, icon: NSImage?, bundleId: String)] = []
        let runningAppList = NSWorkspace.shared.runningApplications
        var addedBundleIds = Set<String>()
        
        _ = getInstalledAppInfo() // Unused
        
        for file in files {
            // 尝试通过 groupId (通常是 bundleId 或应用名) 匹配
            let groupId = file.groupId
            
            // 检查是否有对应的运行中应用
            for app in runningAppList {
                guard let bundleId = app.bundleIdentifier else { continue }
                
                // SKIP SELF: Do not ask to close the current application
                if bundleId == Bundle.main.bundleIdentifier { continue }
                
                // 1. 直接匹配 Bundle ID
                if groupId == bundleId || groupId == bundleId.lowercased() {
                    if !addedBundleIds.contains(bundleId) {
                        runningApps.append((name: app.localizedName ?? file.name, icon: app.icon, bundleId: bundleId))
                        addedBundleIds.insert(bundleId)
                    }
                    continue
                }
                
                // 2. 检查文件路径是否包含 Bundle ID (例如 Containers/com.apple.Safari)
                if file.url.path.contains(bundleId) {
                    if !addedBundleIds.contains(bundleId) {
                        runningApps.append((name: app.localizedName ?? file.name, icon: app.icon, bundleId: bundleId))
                        addedBundleIds.insert(bundleId)
                    }
                    continue
                }
            }
        }
        
        return runningApps
    }
    
    // MARK: - 取消选择特定应用的文件的
    // MARK: - 取消选择特定应用的文件的
    func deselectFiles(for bundleId: String) {
        beginJunkUpdates()
        defer { endJunkUpdates() }
        let lowerBundleId = bundleId.lowercased()
        let shouldDeselect: (CleanerFileItem) -> Bool = { item in
            // Match the original scanned path: an application's bundle ID may
            // appear in an alias name but not in its resolved destination.
            item.groupId.lowercased() == lowerBundleId || item.url.path.lowercased().contains(lowerBundleId)
        }
        let update: ([CleanerFileItem]) -> [CleanerFileItem] = { files in
            var result = files
            for index in result.indices where shouldDeselect(result[index]) {
                result[index].isSelected = false
            }
            return result
        }
        userCacheFiles = update(userCacheFiles)
        systemCacheFiles = update(systemCacheFiles)
        oldUpdateFiles = update(oldUpdateFiles)
        systemLogFiles = update(systemLogFiles)
        userLogFiles = update(userLogFiles)
        localizationFiles = update(localizationFiles)
        largeFiles = update(largeFiles)
        for group in appCacheGroups {
            group.files = group.bundleId?.lowercased() == lowerBundleId
                ? Self.settingSelection(group.files, to: false)
                : update(group.files)
        }
    }
    
    // MARK: - 辅助方法：获取进程内存映射
    private func fetchProcessMemoryMap() async -> [Int32: Int64] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-ax", "-o", "pid,rss"] // All processes: PID, RSS(KB)
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        return await withCheckedContinuation { continuation in
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    var map: [Int32: Int64] = [:]
                    let lines = output.components(separatedBy: "\n")
                    for (index, line) in lines.enumerated() {
                        if index == 0 || line.isEmpty { continue } // Skip header
                        
                        let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        if parts.count >= 2,
                           let pid = Int32(parts[0]),
                           let rssKB = Int64(parts[1]) {
                            map[pid] = rssKB * 1024 // Convert KB to Bytes
                        }
                    }
                    continuation.resume(returning: map)
                } else {
                    continuation.resume(returning: [:])
                }
            } catch {
                print("Error fetching memory map: \(error)")
                continuation.resume(returning: [:])
            }
        }
    }
}

// MARK: - 性能优化应用模型
class PerformanceAppItem: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let icon: NSImage
    let memoryUsage: Int64
    @Published var isSelected: Bool = true
    
    // Legacy support wrapper
    struct LegacyAppWrapper {
        let bundleIdentifier: String?
    }
    var app: LegacyAppWrapper
    
    // For functionality
    let runningApp: NSRunningApplication?
    
    init(name: String, icon: NSImage, memoryUsage: Int64, bundleId: String?, runningApp: NSRunningApplication?) {
        self.name = name
        self.icon = icon
        self.memoryUsage = memoryUsage
        self.app = LegacyAppWrapper(bundleIdentifier: bundleId)
        self.runningApp = runningApp
    }
    
    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: memoryUsage, countStyle: .memory)
    }
}
