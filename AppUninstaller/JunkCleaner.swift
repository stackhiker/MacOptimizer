import Foundation
import Combine
import AppKit

// MARK: - 垃圾类型枚举
enum JunkType: String, CaseIterable, Identifiable {
    case userCache = "用户缓存"
    case systemCache = "系统缓存"
    case userLogs = "用户日志"
    case systemLogs = "系统日志"
    case browserCache = "浏览器缓存"
    case appCache = "应用缓存"
    case chatCache = "聊天缓存"
    case mailAttachments = "邮件附件"
    case crashReports = "崩溃报告"
    case tempFiles = "临时文件"
    case xcodeDerivedData = "Xcode 垃圾"
    // 新增类型
    case universalBinaries = "通用二进制文件"
    case unusedDiskImages = "不使用的磁盘镜像"
    case brokenLoginItems = "损坏的登录项"
    case languageFiles = "语言文件"
    case deletedUsers = "已删除用户"
    case iosBackups = "iOS 设备备份"
    case oldUpdates = "旧更新"
    // ⚠️ brokenPreferences 已移除 - 不再扫描系统偏好设置
    case documentVersions = "文稿版本"
    case downloads = "下载"
    
    var id: String { rawValue }

    var automaticallySelected: Bool {
        switch self {
        case .userCache, .systemCache, .userLogs, .systemLogs, .browserCache,
             .appCache, .chatCache, .tempFiles, .crashReports: return true
        default: return false
        }
    }

    var localizedName: String {
        let loc = LocalizationManager.shared
        switch self {
        case .userCache: return loc.text(simplifiedChinese: "用户缓存", traditionalChinese: "使用者快取", english: "User Cache", japanese: "ユーザーキャッシュ", korean: "사용자 캐시", russian: "Пользовательский кэш")
        case .systemCache: return loc.text(simplifiedChinese: "系统缓存", traditionalChinese: "系統快取", english: "System Cache", japanese: "システムキャッシュ", korean: "시스템 캐시", russian: "Системный кэш")
        case .userLogs: return loc.text(simplifiedChinese: "用户日志", traditionalChinese: "使用者日誌", english: "User Logs", japanese: "ユーザーログ", korean: "사용자 로그", russian: "Пользовательские журналы")
        case .systemLogs: return loc.text(simplifiedChinese: "系统日志", traditionalChinese: "系統日誌", english: "System Logs", japanese: "システムログ", korean: "시스템 로그", russian: "Системные журналы")
        case .browserCache: return loc.text(simplifiedChinese: "浏览器缓存", traditionalChinese: "瀏覽器快取", english: "Browser Cache", japanese: "ブラウザキャッシュ", korean: "브라우저 캐시", russian: "Кэш браузеров")
        case .appCache: return loc.text(simplifiedChinese: "应用缓存", traditionalChinese: "應用程式快取", english: "Application Cache", japanese: "アプリキャッシュ", korean: "앱 캐시", russian: "Кэш приложений")
        case .chatCache: return loc.text(simplifiedChinese: "聊天缓存", traditionalChinese: "聊天快取", english: "Chat Cache", japanese: "チャットキャッシュ", korean: "채팅 캐시", russian: "Кэш мессенджеров")
        case .mailAttachments: return loc.text(simplifiedChinese: "邮件附件", traditionalChinese: "郵件附件", english: "Mail Attachments", japanese: "メール添付ファイル", korean: "메일 첨부 파일", russian: "Почтовые вложения")
        case .crashReports: return loc.text(simplifiedChinese: "崩溃报告", traditionalChinese: "當機報告", english: "Crash Reports", japanese: "クラッシュレポート", korean: "충돌 보고서", russian: "Отчёты о сбоях")
        case .tempFiles: return loc.text(simplifiedChinese: "临时文件", traditionalChinese: "暫存檔案", english: "Temporary Files", japanese: "一時ファイル", korean: "임시 파일", russian: "Временные файлы")
        case .xcodeDerivedData: return loc.text(simplifiedChinese: "Xcode 垃圾", traditionalChinese: "Xcode 垃圾", english: "Xcode Junk", japanese: "Xcode ジャンク", korean: "Xcode 정크", russian: "Мусор Xcode")
        case .universalBinaries: return loc.text(simplifiedChinese: "通用二进制文件", traditionalChinese: "通用二進位檔案", english: "Universal Binaries", japanese: "ユニバーサルバイナリ", korean: "유니버설 바이너리", russian: "Универсальные бинарные файлы")
        case .unusedDiskImages: return loc.text(simplifiedChinese: "未使用的磁盘映像", traditionalChinese: "未使用的磁碟映像", english: "Unused Disk Images", japanese: "未使用のディスクイメージ", korean: "사용하지 않는 디스크 이미지", russian: "Неиспользуемые образы дисков")
        case .brokenLoginItems: return loc.text(simplifiedChinese: "损坏的登录项", traditionalChinese: "損壞的登入項目", english: "Broken Login Items", japanese: "無効なログイン項目", korean: "손상된 로그인 항목", russian: "Неисправные объекты входа")
        case .languageFiles: return loc.text(simplifiedChinese: "语言文件", traditionalChinese: "語言檔案", english: "Language Files", japanese: "言語ファイル", korean: "언어 파일", russian: "Языковые файлы")
        case .deletedUsers: return loc.text(simplifiedChinese: "已删除用户", traditionalChinese: "已刪除的使用者", english: "Deleted Users", japanese: "削除済みユーザー", korean: "삭제된 사용자", russian: "Удалённые пользователи")
        case .iosBackups: return loc.text(simplifiedChinese: "iOS 设备备份", traditionalChinese: "iOS 裝置備份", english: "iOS Device Backups", japanese: "iOSデバイスのバックアップ", korean: "iOS 기기 백업", russian: "Резервные копии iOS")
        case .oldUpdates: return loc.text("安装残留与旧备份", "Installation Residues & Backups")
        case .documentVersions: return loc.text(simplifiedChinese: "文稿版本", traditionalChinese: "文件版本", english: "Document Versions", japanese: "書類のバージョン", korean: "문서 버전", russian: "Версии документов")
        case .downloads: return loc.text(simplifiedChinese: "下载", traditionalChinese: "下載項目", english: "Downloads", japanese: "ダウンロード", korean: "다운로드", russian: "Загрузки")
        }
    }

    var localizedDescription: String {
        let loc = LocalizationManager.shared
        switch self {
        case .userCache: return loc.text(simplifiedChinese: "应用程序产生的临时缓存文件", traditionalChinese: "應用程式產生的暫存快取檔案", english: "Temporary cache files created by applications", japanese: "アプリが作成した一時キャッシュファイル", korean: "앱에서 생성한 임시 캐시 파일", russian: "Временные файлы кэша, созданные приложениями")
        case .systemCache: return loc.text(simplifiedChinese: "macOS 系统产生的缓存", traditionalChinese: "macOS 系統產生的快取", english: "Cache files created by macOS", japanese: "macOSが作成したキャッシュファイル", korean: "macOS에서 생성한 캐시 파일", russian: "Файлы кэша, созданные macOS")
        case .userLogs: return loc.text(simplifiedChinese: "应用程序运行日志", traditionalChinese: "應用程式執行日誌", english: "Application activity logs", japanese: "アプリケーションの動作ログ", korean: "애플리케이션 실행 로그", russian: "Журналы работы приложений")
        case .systemLogs: return loc.text(simplifiedChinese: "macOS 系统日志文件", traditionalChinese: "macOS 系統日誌檔案", english: "macOS system log files", japanese: "macOSのシステムログファイル", korean: "macOS 시스템 로그 파일", russian: "Системные журналы macOS")
        case .browserCache: return loc.text(simplifiedChinese: "Chrome、Safari、Firefox 等浏览器缓存", traditionalChinese: "Chrome、Safari、Firefox 等瀏覽器快取", english: "Caches from Chrome, Safari, Firefox, and other browsers", japanese: "Chrome、Safari、Firefoxなどのブラウザキャッシュ", korean: "Chrome, Safari, Firefox 등의 브라우저 캐시", russian: "Кэш Chrome, Safari, Firefox и других браузеров")
        case .appCache: return loc.text(simplifiedChinese: "各种应用的临时文件", traditionalChinese: "各種應用程式的暫存檔案", english: "Temporary files from applications", japanese: "各アプリケーションの一時ファイル", korean: "여러 앱의 임시 파일", russian: "Временные файлы приложений")
        case .chatCache: return loc.text(simplifiedChinese: "微信、QQ、Telegram 等聊天应用缓存", traditionalChinese: "微信、QQ、Telegram 等聊天應用程式快取", english: "Caches from WeChat, QQ, Telegram, and other messaging apps", japanese: "WeChat、QQ、Telegramなどのチャットアプリのキャッシュ", korean: "WeChat, QQ, Telegram 등의 메신저 캐시", russian: "Кэш WeChat, QQ, Telegram и других мессенджеров")
        case .mailAttachments: return loc.text(simplifiedChinese: "邮件下载的附件文件", traditionalChinese: "郵件下載的附件檔案", english: "Attachments downloaded by mail applications", japanese: "メールアプリがダウンロードした添付ファイル", korean: "메일 앱에서 다운로드한 첨부 파일", russian: "Вложения, загруженные почтовыми приложениями")
        case .crashReports: return loc.text(simplifiedChinese: "应用崩溃产生的诊断报告", traditionalChinese: "應用程式當機產生的診斷報告", english: "Diagnostic reports created when applications crash", japanese: "アプリのクラッシュ時に作成された診断レポート", korean: "앱 충돌 시 생성된 진단 보고서", russian: "Диагностические отчёты о сбоях приложений")
        case .tempFiles: return loc.text(simplifiedChinese: "系统和应用产生的临时文件", traditionalChinese: "系統和應用程式產生的暫存檔案", english: "Temporary files created by the system and applications", japanese: "システムとアプリが作成した一時ファイル", korean: "시스템과 앱에서 생성한 임시 파일", russian: "Временные файлы системы и приложений")
        case .xcodeDerivedData: return loc.text(simplifiedChinese: "Xcode 编译产生的中间文件", traditionalChinese: "Xcode 編譯產生的中間檔案", english: "Intermediate files created by Xcode builds", japanese: "Xcodeのビルドで作成された中間ファイル", korean: "Xcode 빌드에서 생성한 중간 파일", russian: "Промежуточные файлы сборок Xcode")
        case .universalBinaries: return loc.text(simplifiedChinese: "包含多种架构代码的应用二进制文件", traditionalChinese: "包含多種架構程式碼的應用程式二進位檔案", english: "Application binaries containing code for multiple architectures", japanese: "複数のアーキテクチャを含むアプリのバイナリ", korean: "여러 아키텍처 코드를 포함한 앱 바이너리", russian: "Файлы приложений с кодом для нескольких архитектур")
        case .unusedDiskImages: return loc.text(simplifiedChinese: "下载后未使用的 DMG、ISO 和 PKG 文件", traditionalChinese: "下載後未使用的 DMG、ISO 和 PKG 檔案", english: "Unused DMG, ISO, and PKG files in Downloads", japanese: "ダウンロード後に使用されていないDMG、ISO、PKGファイル", korean: "다운로드 후 사용하지 않은 DMG, ISO 및 PKG 파일", russian: "Неиспользуемые файлы DMG, ISO и PKG в папке загрузок")
        case .brokenLoginItems: return loc.text(simplifiedChinese: "指向不存在的应用或文件的登录项", traditionalChinese: "指向不存在應用程式或檔案的登入項目", english: "Login items that point to missing applications or files", japanese: "存在しないアプリやファイルを参照するログイン項目", korean: "존재하지 않는 앱 또는 파일을 가리키는 로그인 항목", russian: "Объекты входа, ссылающиеся на отсутствующие приложения или файлы")
        case .languageFiles: return loc.text(simplifiedChinese: "当前不使用的应用程序语言包", traditionalChinese: "目前未使用的應用程式語言套件", english: "Application language resources not currently in use", japanese: "現在使用していないアプリの言語リソース", korean: "현재 사용하지 않는 앱 언어 리소스", russian: "Неиспользуемые языковые ресурсы приложений")
        case .deletedUsers: return loc.text(simplifiedChinese: "已删除用户留下的数据", traditionalChinese: "已刪除使用者留下的資料", english: "Data left behind by deleted user accounts", japanese: "削除済みユーザーアカウントの残存データ", korean: "삭제된 사용자 계정의 잔여 데이터", russian: "Данные, оставшиеся от удалённых учётных записей")
        case .iosBackups: return loc.text(simplifiedChinese: "存储在本机的 iOS 设备备份", traditionalChinese: "儲存在本機的 iOS 裝置備份", english: "iOS device backups stored on this Mac", japanese: "このMacに保存されたiOSデバイスのバックアップ", korean: "이 Mac에 저장된 iOS 기기 백업", russian: "Резервные копии устройств iOS на этом Mac")
        case .oldUpdates: return loc.text("旧安装暂存与回滚副本，确认不再需要后再选择。", "Old installation files and rollback copies. Select only after review.")
        case .documentVersions: return loc.text(simplifiedChinese: "文稿的旧版本历史记录", traditionalChinese: "文件的舊版本歷史記錄", english: "History of older document versions", japanese: "書類の古いバージョン履歴", korean: "문서의 이전 버전 기록", russian: "История предыдущих версий документов")
        case .downloads: return loc.text(simplifiedChinese: "下载文件夹中的文件", traditionalChinese: "下載項目檔案夾中的檔案", english: "Files in the Downloads folder", japanese: "ダウンロードフォルダ内のファイル", korean: "다운로드 폴더의 파일", russian: "Файлы в папке «Загрузки»")
        }
    }
    
    var icon: String {
        switch self {
        case .userCache: return "person.crop.circle.fill" // User Cache
        case .systemCache: return "gear.circle.fill" // System Cache
        case .userLogs: return "doc.text.fill" // User Logs
        case .systemLogs: return "doc.text.fill" // System Logs
        case .appCache: return "square.stack.3d.up.fill"
        case .browserCache: return "globe.americas.fill"
        case .chatCache: return "message.fill"
        case .mailAttachments: return "envelope.fill"
        case .crashReports: return "exclamationmark.triangle.fill"
        case .tempFiles: return "clock.fill"
        case .xcodeDerivedData: return "hammer.fill"
        // New Types Icons
        case .unusedDiskImages: return "externaldrive.fill" // Disk Image
        case .universalBinaries: return "cpu.fill" // Universal Binary
        case .brokenLoginItems: return "person.badge.minus" // Broken Login
        case .deletedUsers: return "person.crop.circle.badge.xmark" // Deleted Users
        case .iosBackups: return "iphone.circle.fill" // iOS Backups
        case .oldUpdates: return "arrow.down.doc.fill" // Updates
        // brokenPreferences 已移除
        case .documentVersions: return "doc.on.doc.fill"
        case .languageFiles: return "globe"
        case .downloads: return "arrow.down.circle.fill"
        }
    }
    
    var description: String {
        switch self {
        case .userCache: return "应用程序产生的临时缓存文件"
        case .systemCache: return "macOS 系统产生的缓存"
        case .userLogs: return "应用程序运行日志"
        case .systemLogs: return "macOS 系统日志文件"
        case .browserCache: return "Chrome、Safari、Firefox 等浏览器缓存"
        case .appCache: return "各种应用的临时文件"
        case .chatCache: return "微信、QQ、Telegram 等聊天记录缓存"
        case .mailAttachments: return "邮件下载的附件文件"
        case .crashReports: return "应用崩溃产生的诊断报告"
        case .tempFiles: return "系统和应用产生的临时文件"
        case .xcodeDerivedData: return "Xcode 编译产生的中间文件"
        // 新增描述
        case .universalBinaries: return "支持多种系统架构的应用程序冗余代码"
        case .unusedDiskImages: return "下载后未使用的 DMG/ISO 镜像文件"
        case .brokenLoginItems: return "指向不存在的应用或文件的登录项"
        case .languageFiles: return "不使用的应用程序语言包"
        case .deletedUsers: return "已删除用户的残留数据"
        case .iosBackups: return "iOS 设备备份文件"
        case .oldUpdates: return "旧安装暂存与回滚副本，需确认"
        // brokenPreferences 已移除 - 不再扫描系统偏好设置
        case .documentVersions: return "旧版本的文档历史记录"
        case .downloads: return "下载文件夹中的文件"
        }
    }
    
    var searchPaths: [String] {
        // SAFETY: Only scan user home (~/) paths. NEVER scan system paths.
        switch self {
        case .userCache:
            return ["~/Library/Caches"]
        case .systemCache:
            // 扫描用户级别的系统缓存
            return [
                "~/Library/Caches"
            ]
        case .userLogs: 
            return [
                "~/Library/Logs",
                "~/Library/Application Support/CrashReporter"
            ]
        case .systemLogs:
            // Removed /Library/Logs, /private/var/log - only user logs
            return [
                "~/Library/Logs"
            ]
        case .browserCache: 
            // 仅包含安全的缓存路径，已移除包含登录信息的目录
            // 注意: 已移除 IndexedDB, LocalStorage, Databases, Firefox/Profiles, CacheStorage - 这些包含用户登录信息
            return [
                // Chrome - 安全缓存
                "~/Library/Caches/Google/Chrome",
                "~/Library/Application Support/Google/Chrome/Default/Cache",
                "~/Library/Application Support/Google/Chrome/Default/Code Cache",
                "~/Library/Application Support/Google/Chrome/Default/GPUCache",
                "~/Library/Application Support/Google/Chrome/ShaderCache",
                // Safari - 仅 Caches 安全
                "~/Library/Caches/com.apple.Safari",
                // Firefox - 仅 Caches 安全 (已移除 Profiles - 包含历史和登录)
                "~/Library/Caches/Firefox",
                // Edge - 安全缓存
                "~/Library/Caches/Microsoft Edge",
                "~/Library/Application Support/Microsoft Edge/Default/Cache",
                "~/Library/Application Support/Microsoft Edge/Default/Code Cache",
                // Arc - 安全缓存
                "~/Library/Caches/company.thebrowser.Browser",
                "~/Library/Application Support/Arc/User Data/Default/Cache",
                // Brave - 安全缓存
                "~/Library/Caches/BraveSoftware",
                "~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache",
                // Opera
                "~/Library/Caches/com.operasoftware.Opera",
                // Vivaldi
                "~/Library/Caches/com.vivaldi.Vivaldi"
            ]
        case .appCache:
            return [] // Dynamic scanning implemented in scanTypeConcurrent
        case .chatCache:
            // 注意：仅扫描 ~/Library/Caches 和 ~/Library/Application Support 中的安全路径
            // 不扫描 ~/Library/Containers/<other-app> 目录，因为会触发 macOS 权限弹窗
            return [
                // 微信 - 仅 Caches 目录
                "~/Library/Caches/com.tencent.xinWeChat",
                // QQ - 仅 Caches 目录
                "~/Library/Caches/com.tencent.qq",
                // Telegram
                "~/Library/Caches/ru.keepcoder.Telegram",
                // Slack
                "~/Library/Caches/com.tinyspeck.slackmacgap",
                "~/Library/Application Support/Slack/Service Worker/CacheStorage",
                // Discord
                "~/Library/Caches/com.hnc.Discord",
                "~/Library/Application Support/discord/Cache",
                "~/Library/Application Support/discord/Code Cache",
                // WhatsApp
                "~/Library/Caches/net.whatsapp.WhatsApp",
                "~/Library/Application Support/WhatsApp/Cache",
                // Line
                "~/Library/Caches/jp.naver.line.mac",
                // iMessage 附件（可选择性清理）
            ]
        case .mailAttachments:
            return [
                "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
                "~/Library/Mail Downloads",
                "~/Library/Caches/com.apple.mail",
                "~/Library/Group Containers/UBF8T346G9.Office/Outlook/Outlook 15 Profiles/Main Profile/Data/Attachments",
                "~/Library/Containers/com.readdle.smartemail-Mac/Data/Library/Application Support/Spark Desktop/attachments"
            ]
        case .crashReports:
            // Removed /Library paths - only user crash reports
            return [
                "~/Library/Logs/DiagnosticReports",
                "~/Library/Application Support/CrashReporter"
            ]
        case .tempFiles:
            // Removed /tmp, /private - only user temp files
            return [
                "~/Library/Application Support/CrashReporter",
                "~/Library/Caches/com.apple.helpd",
                "~/Library/Caches/CloudKit",
                "~/Library/Caches/GeoServices",
                "~/Library/Caches/com.apple.parsecd",
            ]
        case .xcodeDerivedData: 
            return [
                "~/Library/Developer/Xcode/DerivedData",
                "~/Library/Developer/CoreSimulator/Caches",
                "~/Library/Developer/Xcode/iOS DeviceSupport",
                "~/Library/Developer/Xcode/watchOS DeviceSupport",
                "~/Library/Developer/Xcode/tvOS DeviceSupport",
                "~/Library/Caches/com.apple.dt.Xcode",
                // CocoaPods
                "~/Library/Caches/CocoaPods",
                // npm/yarn/pnpm
                "~/.npm/_cacache",
                "~/.npm/_logs",
                "~/Library/Caches/Yarn",
                // Gradle/Maven
                "~/.gradle/caches",
                // Homebrew
                "~/Library/Caches/Homebrew",
                // pip
                "~/Library/Caches/pip",
                // Ruby/Gem
                // Go
                "~/go/pkg/mod/cache"
            ]
        // DISABLED TYPES - These are risky or require system access
        case .universalBinaries:
            return ["/Applications", "/System/Applications", "/System/Applications/Utilities", "~/Applications"]
        case .unusedDiskImages:
            return ["~"] // Scan full user home directory recursively
        case .brokenLoginItems:
            return ["~/Library/LaunchAgents"]
        case .languageFiles:
            return [] // Custom logic
        case .deletedUsers:
            return [] // Account data is not disposable junk.
        case .iosBackups:
            return [] // Device backups require a dedicated review workflow.
        case .oldUpdates:
            return [] // InstallationResidueScanner owns the exact roots and rules.
        // brokenPreferences 已移除 - 不再扫描系统偏好设置
        case .documentVersions:
            return [] // Document history must not be classified as junk.
        case .downloads:
            return ["~/Downloads"]
        }
    }
}

// MARK: - 垃圾项模型
class JunkItem: Identifiable, ObservableObject, @unchecked Sendable {
    let id = UUID()
    let type: JunkType
    let path: URL
    let contextPath: URL? // Path for the actual operation (e.g., binary to strip), while `path` is for display (App Bundle)
    let customName: String? // Optional custom display name
    let size: Int64
    let installationResidue: InstallationResidue?
    @Published var isSelected: Bool = true
    @Published var cleanupRecommendation: CleanupAdvice? = nil
    
    init(type: JunkType, path: URL, size: Int64, contextPath: URL? = nil, customName: String? = nil,
         installationResidue: InstallationResidue? = nil) {
        self.type = type
        self.path = path
        self.size = size
        self.contextPath = contextPath
        self.customName = customName
        self.installationResidue = installationResidue
        self.isSelected = installationResidue == nil && type.automaticallySelected
    }
    
    var name: String {
        customName ?? path.lastPathComponent
    }
}

// MARK: - 垃圾清理服务
class JunkCleaner: ObservableObject {
    @Published var junkItems: [JunkItem] = []
    @Published var isScanning: Bool = false
    @Published var isScanningMailAttachments: Bool = false
    @Published var hasScannedMailAttachments: Bool = false
    @Published var mailScanProgress: Double = 0
    @Published var mailAttachmentsHavePermissionError: Bool = false
    @Published var isCleaningMailAttachments: Bool = false
    @Published var mailCleaningProgress: Double = 0
    @Published var mailCleanedSize: Int64 = 0
    @Published var isAnalyzingRecommendations: Bool = false
    @Published var isCleaning: Bool = false  // 添加清理状态
    @Published var stopCleaningRequested: Bool = false
    @Published var scanProgress: Double = 0
    @Published var hasPermissionErrors: Bool = false
    @Published var currentScanningPath: String = "" // Add path tracking
    @Published var currentScanningCategory: String = "" // Add category tracking
    
    // MARK: - 分类清理进度跟踪
    /// 正在清理的分类列表（按顺序）
    @Published var cleaningCategories: [JunkType] = []
    /// 当前正在清理的分类
    @Published var currentCleaningCategory: JunkType? = nil
    /// 每个分类的清理状态: pending, cleaning, completed
    @Published var categoryCleaningStatus: [JunkType: CleaningStatus] = [:]
    /// 每个分类的清理大小
    @Published var categoryCleanedSize: [JunkType: Int64] = [:]
    
    enum CleaningStatus: String {
        case pending = "pending"      // 等待清理
        case cleaning = "cleaning"    // 正在清理
        case completed = "completed"  // 清理完成
    }
    
    private let fileManager = FileManager.default
    private var mailScanGeneration = UUID()
    private var stopMailCleaningRequested = false
    var mailCleaningWasStopped: Bool { stopMailCleaningRequested }
    private var scanTask: Task<Void, Never>?
    private var mailScanTask: Task<Void, Never>?
    private var cleanupIsActive = false
    private let scanOverride: ((JunkType) async -> ([JunkItem], Bool))?
    private let deleteFile: (URL) async throws -> Void
    private let deletionAllowed: (URL, Bool) -> Bool
    private let recordFailure: (RemovalFailure) -> Void
    private let scanInstallationResidues: () async -> [InstallationResidue]
    private let validateInstallationResidue: (InstallationResidue) async -> Bool
    @Published var deletionFailures: [RemovalFailure] = []
    @Published var diskSpaceChange: Int64?
    @Published var cleanedItemCount = 0

    init(scanType: ((JunkType) async -> ([JunkItem], Bool))? = nil,
         deleteFile: @escaping (URL) async throws -> Void = {
             try DeletionLogService.shared.trashItem(at: $0, category: "JunkClean")
         }, deletionAllowed: @escaping (URL, Bool) -> Bool = {
             SafetyGuard.shared.isSafeToDelete($0, ignoreProtection: $1)
         }, recordFailure: @escaping (RemovalFailure) -> Void = {
             DeletionLogService.shared.logFailure($0, category: "JunkClean")
         }, scanInstallationResidues: @escaping () async -> [InstallationResidue] = {
             await InstallationResidueScanner().scan()
         }, validateInstallationResidue: @escaping (InstallationResidue) async -> Bool = {
             await SafetyGuard.shared.isSafeToDeleteInstallationResidue($0)
         }) {
        self.scanOverride = scanType
        self.deleteFile = deleteFile
        self.deletionAllowed = deletionAllowed
        self.recordFailure = recordFailure
        self.scanInstallationResidues = scanInstallationResidues
        self.validateInstallationResidue = validateInstallationResidue
    }

    static func uniqueItems(_ items: [JunkItem]) -> [JunkItem] {
        var byPath: [String: JunkItem] = [:]
        for item in items where byPath[item.path.standardizedFileURL.path] == nil {
            byPath[item.path.standardizedFileURL.path] = item
        }
        return CleanupFileSystem.uniqueRoots(items.map(\.path)).compactMap { byPath[$0.path] }
    }

    static func shouldSelectByDefault(_ item: JunkItem) -> Bool {
        guard item.installationResidue == nil, item.type.automaticallySelected else { return false }
        if let advice = item.cleanupRecommendation { return advice.decision == .recommended }
        return true
    }
    
    var totalSize: Int64 {
        junkItems.reduce(0) { $0 + $1.size }
    }
    
    var selectedSize: Int64 {
        junkItems.filter { $0.isSelected }.reduce(0) { $0 + $1.size }
    }
    
    /// 重置所有状态
    @MainActor
    func reset() {
        guard scanTask == nil, mailScanTask == nil, !cleanupIsActive else {
            scanTask?.cancel()
            mailScanTask?.cancel()
            stopCleaningRequested = true
            stopMailCleaningRequested = true
            return
        }
        junkItems.removeAll()
        isScanning = false
        isAnalyzingRecommendations = false
        isCleaning = false
        stopCleaningRequested = false
        scanProgress = 0
        hasPermissionErrors = false
        currentScanningPath = ""
        currentScanningCategory = ""
        // 重置分类清理状态
        cleaningCategories.removeAll()
        currentCleaningCategory = nil
        categoryCleaningStatus.removeAll()
        categoryCleanedSize.removeAll()
    }

    /// Reset only the Mail Attachments module without discarding System Junk results.
    @MainActor
    func resetMailAttachments() {
        guard mailScanTask == nil, !cleanupIsActive else {
            mailScanTask?.cancel()
            stopMailCleaningRequested = true
            return
        }
        mailScanGeneration = UUID()
        junkItems.removeAll { $0.type == .mailAttachments }
        isScanningMailAttachments = false
        hasScannedMailAttachments = false
        mailScanProgress = 0
        mailAttachmentsHavePermissionError = false
        isCleaningMailAttachments = false
        mailCleaningProgress = 0
        mailCleanedSize = 0
        stopMailCleaningRequested = false
    }

    /// Mail scans share operation ownership with the general scanner.
    @MainActor
    func scanMailAttachments() async {
        guard scanTask == nil, mailScanTask == nil, !cleanupIsActive else { return }
        isScanningMailAttachments = true
        hasScannedMailAttachments = false
        mailAttachmentsHavePermissionError = false
        junkItems.removeAll { $0.type == .mailAttachments }
        let task = Task {
            let (items, permissionError) = await scanTypeConcurrent(.mailAttachments)
            guard !Task.isCancelled else { return }
            junkItems.append(contentsOf: Self.uniqueItems(items).sorted { $0.size > $1.size })
            mailAttachmentsHavePermissionError = permissionError
            mailScanProgress = 1
            hasScannedMailAttachments = true
        }
        mailScanTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        mailScanTask = nil
        isScanningMailAttachments = false
    }

    @MainActor
    func stopMailAttachmentsScan() {
        mailScanTask?.cancel()
    }

    /// Clean only selected mail attachments, keeping all unrelated module
    /// selections untouched.
    @MainActor
    func cleanSelectedMailAttachments() async -> (cleaned: Int64, failed: Int64) {
        guard !cleanupIsActive, scanTask == nil, mailScanTask == nil else { return (0, 0) }
        cleanupIsActive = true
        deletionFailures = []
        cleanedItemCount = 0
        diskSpaceChange = nil
        let before = CleanupDiskSnapshot.capture()
        defer {
            cleanupIsActive = false
            isCleaningMailAttachments = false
            diskSpaceChange = CleanupDiskSnapshot.capture()?.change(since: before)
        }
        let selectedItems = await MainActor.run {
            Self.uniqueItems(junkItems.filter { $0.type == .mailAttachments && $0.isSelected })
        }

        await MainActor.run {
            stopMailCleaningRequested = false
            isCleaningMailAttachments = true
            mailCleaningProgress = 0
            mailCleanedSize = 0
        }

        var cleaned: Int64 = 0
        var failed: Int64 = 0
        var cleanedIDs = Set<UUID>()

        for (index, item) in selectedItems.enumerated() {
            if stopMailCleaningRequested || Task.isCancelled { break }

            if await deleteItem(item) {
                cleaned += item.size
                cleanedIDs.insert(item.id)
                cleanedItemCount += 1
            } else {
                failed += item.size
            }

            let progress = selectedItems.isEmpty ? 1 : Double(index + 1) / Double(selectedItems.count)
            let currentCleaned = cleaned
            await MainActor.run {
                mailCleaningProgress = progress
                mailCleanedSize = currentCleaned
            }
        }

        let completedIDs = cleanedIDs
        await MainActor.run {
            junkItems.removeAll { item in
                selectedItems.contains { selected in completedIDs.contains(selected.id) && CleanupFileSystem.contains(item.path, in: selected.path) }
            }
            isCleaningMailAttachments = false
            DiskSpaceManager.shared.updateDiskSpace()
        }

        return (cleaned, failed)
    }

    @MainActor
    func stopMailAttachmentsCleaning() {
        stopMailCleaningRequested = true
    }
    
    /// Keep ownership until all children have observed cancellation.
    @MainActor
    func stopScanning() {
        scanTask?.cancel()
    }

    @MainActor
    func stopCleaning() {
        stopCleaningRequested = true
    }

    @MainActor
    func scanJunk() async {
        guard scanTask == nil, mailScanTask == nil, !cleanupIsActive else { return }
        isScanning = true
        isAnalyzingRecommendations = false
        junkItems.removeAll()
        categoryCleanedSize.removeAll()
        scanProgress = 0
        hasPermissionErrors = false
        let task = Task { await self.performScan() }
        scanTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        scanTask = nil
        isScanning = false
        isAnalyzingRecommendations = false
        currentScanningPath = ""
        currentScanningCategory = ""
    }

    private func scanCategory(_ type: JunkType) async -> ([JunkItem], Bool) {
        if let scanOverride { return await scanOverride(type) }
        return await scanTypeConcurrent(type)
    }

    private func performScan() async {
        let types = JunkType.allCases
        var completed = 0
        var iterator = types.makeIterator()
        await withTaskGroup(of: ([JunkItem], Bool).self) { group in
            for _ in 0..<min(4, types.count) {
                if let type = iterator.next() {
                    group.addTask { await self.scanCategory(type) }
                }
            }
            while let (items, error) = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); break }
                completed += 1
                let progress = Double(completed) / Double(types.count)
                await MainActor.run {
                    self.hasPermissionErrors = self.hasPermissionErrors || error
                    self.junkItems = Self.uniqueItems(self.junkItems + items.filter { ScanResultIgnoreStore.shouldInclude($0.path) })
                    self.scanProgress = progress
                }
                if let type = iterator.next() {
                    group.addTask { await self.scanCategory(type) }
                }
            }
        }
        guard !Task.isCancelled else { return }
        await MainActor.run { self.junkItems.sort { $0.size > $1.size } }
        await analyzeCleanupRecommendations()
    }

    private func analyzeCleanupRecommendations() async {
        let items = await MainActor.run { self.junkItems }
        guard !items.isEmpty else { return }
        
        await MainActor.run {
            self.isAnalyzingRecommendations = true
            for item in self.junkItems {
                item.cleanupRecommendation = .pending
            }
        }
        
        let recommendations = await CleanupAdvisorService.shared.analyze(items: items)
        guard !Task.isCancelled else { return }
        
        await MainActor.run {
            for item in self.junkItems {
                guard let recommendation = recommendations[item.id] else { continue }
                item.cleanupRecommendation = recommendation
                item.isSelected = Self.shouldSelectByDefault(item)
            }
            self.isAnalyzingRecommendations = false
            self.objectWillChange.send()
        }
    }
    
    /// Roots and entries are streamed inside each of at most four category tasks.
    private func scanTypeConcurrent(_ type: JunkType) async -> ([JunkItem], Bool) {
        if type == .universalBinaries || type == .languageFiles { return ([], false) }
        if type == .oldUpdates {
            let candidates = await scanInstallationResidues()
            guard !Task.isCancelled else { return ([], false) }
            return (candidates.filter { ScanResultIgnoreStore.shouldInclude($0.url) }.map {
                JunkItem(type: .oldUpdates, path: $0.url, size: $0.size,
                         customName: $0.name, installationResidue: $0)
            }, false)
        }
        var items: [JunkItem] = []
        var permissionError = false
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        for path in type.searchPaths {
            guard !Task.isCancelled else { break }
            let root = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            await MainActor.run {
                self.currentScanningPath = root.path
                self.currentScanningCategory = type.localizedName
            }
            guard fileManager.fileExists(atPath: root.path) else { continue }
            // Inspect permission errors instead of silently claiming a complete scan.
            var errors: [NSError] = []
            guard let entries = fileManager.enumerator(at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in
                    errors.append(error as NSError)
                    return !Task.isCancelled
                }) else { continue }
            for case let url as URL in entries {
                guard !Task.isCancelled else { break }
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if values.isSymbolicLink == true { entries.skipDescendants(); continue }
                if InstallationResidueScanner.excludesGenericCleanup(url) {
                    // Recursive disk-image discovery may pass through an ancestor,
                    // but must never enter a managed runtime/backup root itself.
                    let ancestorOnly = values.isDirectory == true &&
                        InstallationResidueScanner.managedRootPaths.contains { $0.hasPrefix(url.path + "/") }
                    if type != .unusedDiskImages || !ancestorOnly { entries.skipDescendants() }
                    continue
                }
                if type != .unusedDiskImages { entries.skipDescendants() }
                if type == .unusedDiskImages {
                    guard values.isRegularFile == true,
                          ["dmg", "iso", "pkg"].contains(url.pathExtension.lowercased()),
                          let modified = values.contentModificationDate,
                          modified < Date().addingTimeInterval(-30 * 86400) else { continue }
                }
                if type == .brokenLoginItems {
                    guard url.pathExtension == "plist", let plist = NSDictionary(contentsOf: url) else { continue }
                    let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                    guard let program, program.hasPrefix("/"), !fileManager.fileExists(atPath: program) else { continue }
                }
                let size = await calculateSizeAsync(at: url)
                if size > 0 { items.append(JunkItem(type: type, path: url, size: size)) }
            }
            permissionError = permissionError || errors.contains {
                ($0.domain == NSCocoaErrorDomain && $0.code == NSFileReadNoPermissionError) ||
                ($0.domain == NSPOSIXErrorDomain && [$0.code].contains(Int(EACCES)))
            }
        }
        return (Self.uniqueItems(items).filter { ScanResultIgnoreStore.shouldInclude($0.path) }, permissionError)
    }

    private func calculateSizeAsync(at url: URL) async -> Int64 {
        CleanupFileSystem.logicalSize(at: url, shouldCancel: { Task.isCancelled })
    }

    func cleanSelected() async -> (cleaned: Int64, failed: Int64, requiresAdmin: Bool) {
        await cleanSelectedByCategory()
    }

    /// 逐分类清理选中的垃圾 - 按设计图要求逐个分类清理并显示进度
    @MainActor
    func cleanSelectedByCategory() async -> (cleaned: Int64, failed: Int64, requiresAdmin: Bool) {
        guard !cleanupIsActive, scanTask == nil, mailScanTask == nil else { return (0, 0, false) }
        cleanupIsActive = true
        isCleaning = true
        deletionFailures = []
        cleanedItemCount = 0
        diskSpaceChange = nil
        let before = CleanupDiskSnapshot.capture()
        defer {
            diskSpaceChange = CleanupDiskSnapshot.capture()?.change(since: before)
            cleanupIsActive = false
            isCleaning = false
        }
        var totalCleanedSize: Int64 = 0
        var totalFailedSize: Int64 = 0
        var needsAdmin = false
        var cleanedItemIDs = Set<UUID>()

        await MainActor.run {
            self.stopCleaningRequested = false
        }
        
        // 1. 获取所有有选中项目的分类（按大小降序排列）
        let selectedItems = Self.uniqueItems(junkItems.filter { $0.isSelected })
        let categorySizes: [JunkType: Int64] = Dictionary(grouping: selectedItems, by: { $0.type })
            .mapValues { items in items.reduce(0) { $0 + $1.size } }
        
        let sortedCategories = categorySizes.keys.sorted { 
            categorySizes[$0] ?? 0 > categorySizes[$1] ?? 0 
        }
        
        // 2. 初始化分类清理状态
        await MainActor.run {
            self.cleaningCategories = sortedCategories
            self.categoryCleaningStatus = Dictionary(uniqueKeysWithValues: sortedCategories.map { ($0, .pending) })
            self.categoryCleanedSize = [:]
        }
        
        // 3. 逐个分类清理
        for category in sortedCategories {
            if stopCleaningRequested || Task.isCancelled { break }

            await MainActor.run {
                self.currentCleaningCategory = category
                self.categoryCleaningStatus[category] = .cleaning
            }
            
            // 获取该分类的选中项目
            let categoryItems = selectedItems.filter { $0.type == category }
            var categoryCleanedSize: Int64 = 0
            var categoryFailedItems: [JunkItem] = []
            
            // 清理该分类的所有文件
            for item in categoryItems {
                if stopCleaningRequested || Task.isCancelled { break }

                let success = await deleteItem(item)
                if success {
                    categoryCleanedSize += item.size
                    totalCleanedSize += item.size
                    cleanedItemIDs.insert(item.id)
                    cleanedItemCount += 1
                } else {
                    totalFailedSize += item.size
                    categoryFailedItems.append(item)
                }
                
                // 更新进度 - 先捕获值以避免 Swift 6 警告
                let currentCleanedSize = categoryCleanedSize
                await MainActor.run {
                    self.categoryCleanedSize[category] = currentCleanedSize
                }
            }
            
            needsAdmin = needsAdmin || !categoryFailedItems.isEmpty

            // 标记该分类完成
            await MainActor.run {
                self.categoryCleaningStatus[category] = .completed
            }
            
            await Task.yield()
        }
        
        // 4. 从 junkItems 中移除已清理的项目
        let completedItemIDs = cleanedItemIDs
        await MainActor.run {
            self.junkItems.removeAll { item in
                selectedItems.contains { selected in completedItemIDs.contains(selected.id) && CleanupFileSystem.contains(item.path, in: selected.path) }
            }
            self.currentCleaningCategory = nil
            DiskSpaceManager.shared.updateDiskSpace()
        }
        
        return (totalCleanedSize, totalFailedSize, needsAdmin)
    }
    
    /// 检查应用是否可以安全瘦身
    // canSafelyThinApp、thinUniversalBinary、reSignApp 已移除 - 通用二进制瘦身功能已禁用
    
    /// Safety refusals and filesystem failures remain visible with their real reason.
    private func deleteItem(_ item: JunkItem) async -> Bool {
        do {
            let explicitUserFile = item.type == .downloads || item.type == .unusedDiskImages || item.type == .mailAttachments
            let allowed: Bool
            if let residue = item.installationResidue {
                allowed = item.type == .oldUpdates && item.contextPath == nil &&
                    item.path.standardizedFileURL == residue.url.standardizedFileURL
                    ? await validateInstallationResidue(residue) : false
            } else {
                allowed = !InstallationResidueScanner.excludesGenericCleanup(item.path) &&
                    deletionAllowed(item.path, explicitUserFile)
            }
            guard allowed else {
                throw NSError(domain: "CleanupSafety", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    LocalizationManager.shared.text("此项目受保护或仍在使用，已保留。", "This item is protected or in use and was retained.")])
            }
            let stopped = isCleaningMailAttachments ? stopMailCleaningRequested : stopCleaningRequested
            guard !stopped, !Task.isCancelled else { return false }
            try await deleteFile(item.path)
            return true
        } catch {
            let failure = RemovalFailure(path: item.path, error: error)
            recordFailure(failure)
            await MainActor.run { deletionFailures.append(failure) }
            return false
        }
    }

}
