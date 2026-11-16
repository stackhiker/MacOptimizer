import SwiftUI

// MARK: - 扫描状态
enum TrashScanState {
    case initial    // 初始页面
    case scanning   // 扫描中
    case completed  // 扫描完成（结果页）
    case clean      // 扫描完成且无文件
    case cleaning   // 清理中
    case finished   // 清理完成
}

struct TrashItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let size: Int64
    let dateDeleted: Date?
    let isDirectory: Bool
    var isSelected: Bool = true
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    var formattedDate: String {
        guard let date = dateDeleted else { return "未知" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

class TrashScanner: ObservableObject {
    @Published var items: [TrashItem] = []
    @Published var isScanning = false
    @Published var totalSize: Int64 = 0
    @Published var hasCompletedScan = false
    @Published var needsPermission = false
    @Published var scannedItemCount = 0
    @Published var isStopped = false
    @Published private(set) var isStoppingScan = false
    @Published var currentScanPath = ""
    @Published var isCleaning = false
    @Published var cleanedCount = 0
    /// Logical bytes permanently deleted; observed disk change is reported separately.
    @Published var cleanedSize: Int64 = 0
    @Published var failedDeletionCount = 0
    @Published var cleaningWasStopped = false
    @Published private(set) var deletionFailures: [RemovalFailure] = []
    @Published private(set) var scanFailure: RemovalFailure?
    @Published private(set) var diskSpaceChange: Int64?

    private let fileManager = FileManager.default
    let trashURL: URL
    @MainActor private var scanTask: Task<Void, Never>?
    @MainActor private var activeScanID: UUID?
    @MainActor private var shouldStopCleaning = false
    private let listItems: (URL) async throws -> [URL]
    private let measureSize: (URL) async -> Int64
    private let removeItem: (URL) async throws -> Void
    private let recordFailure: (RemovalFailure) -> Void

    init(trashURL: URL? = nil,
         listItems: @escaping (URL) async throws -> [URL] = {
             try FileManager.default.contentsOfDirectory(at: $0,
                 includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey])
         },
         measureSize: @escaping (URL) async -> Int64 = {
             CleanupFileSystem.logicalSize(at: $0, shouldCancel: { Task.isCancelled })
         },
         removeItem: @escaping (URL) async throws -> Void = { try FileManager.default.removeItem(at: $0) },
         recordFailure: @escaping (RemovalFailure) -> Void = {
             DeletionLogService.shared.logFailure($0, category: "EmptyTrash")
         }) {
        let systemTrash = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false)) ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let requestedRoot = (trashURL ?? systemTrash).standardizedFileURL
        // Resolve harmless ancestor aliases such as /var, but keep the final
        // Trash component intact so an existing symlink cannot become trusted.
        self.trashURL = requestedRoot.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(requestedRoot.lastPathComponent, isDirectory: true).standardizedFileURL
        self.listItems = listItems
        self.measureSize = measureSize
        self.removeItem = removeItem
        self.recordFailure = recordFailure
    }

    var selectedSize: Int64 { uniqueItems(items.filter(\.isSelected)).reduce(0) { $0 + $1.size } }
    var formattedSelectedSize: String { ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file) }
    var formattedTotalSize: String { ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file) }

    @MainActor
    func toggleSelection(_ item: TrashItem) {
        guard !isScanning, !isCleaning else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].isSelected.toggle() }
    }

    @MainActor
    func toggleAllSelection(_ selected: Bool) {
        guard !isScanning, !isCleaning else { return }
        for index in items.indices { items[index].isSelected = selected }
    }

    @MainActor
    func stopScan() {
        guard let scanTask else { return }
        isStopped = true
        isStoppingScan = true
        currentScanPath = LocalizationManager.shared.text("正在停止扫描…", "Stopping scan…")
        scanTask.cancel()
    }

    @MainActor
    func stopCleaning() {
        guard isCleaning else { return }
        shouldStopCleaning = true
        cleaningWasStopped = true
    }

    @MainActor
    func scan() async {
        guard scanTask == nil, !isScanning, !isCleaning, !Task.isCancelled else { return }
        reset()
        isScanning = true
        let id = UUID()
        activeScanID = id
        let task = Task { await self.performScan(id: id) }
        scanTask = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        guard activeScanID == id else { return }
        isStopped = isStopped || task.isCancelled
        activeScanID = nil
        scanTask = nil
        isScanning = false
        isStoppingScan = false
        currentScanPath = ""
        hasCompletedScan = !isStopped && scanFailure == nil
    }

    private func performScan(id: UUID) async {
        var scanned: [TrashItem] = []
        do {
            let attributes = try fileManager.attributesOfItem(atPath: trashURL.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  trashURL.resolvingSymlinksInPath().path == trashURL.path else {
                throw NSError(domain: "MacOptimizer.TrashSafety", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: LocalizationManager.shared.text(
                        "废纸篓路径不是受信任的文件夹，未扫描或删除其中的项目。", "The Trash path is not a trusted directory. Its contents were not scanned or removed.")])
            }
            let contents = try await listItems(trashURL)
            var lastPublish = Date.distantPast
            for url in contents {
                guard !Task.isCancelled else { return }
                guard isDirectTrashChild(url), ScanResultIgnoreStore.shouldInclude(url) else { continue }
                let size = await measureSize(url)
                guard !Task.isCancelled else { return }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey])
                scanned.append(TrashItem(url: url, name: url.lastPathComponent, size: size,
                    dateDeleted: values?.contentModificationDate,
                    isDirectory: values?.isDirectory == true && values?.isSymbolicLink != true))
                let now = Date()
                if now.timeIntervalSince(lastPublish) >= 0.1 {
                    lastPublish = now
                    let count = scanned.count
                    await MainActor.run {
                        guard activeScanID == id, !isStoppingScan else { return }
                        currentScanPath = url.path
                        scannedItemCount = count
                    }
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            let error = error as NSError
            // A missing Trash folder is an empty Trash, not a permissions error.
            if !(error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError) {
                let failure = RemovalFailure(path: trashURL, error: error)
                await MainActor.run {
                    guard activeScanID == id, !isStoppingScan else { return }
                    scanFailure = failure
                    needsPermission = (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError)
                        || (error.domain == NSPOSIXErrorDomain && (error.code == Int(EACCES) || error.code == Int(EPERM)))
                }
            }
        }
        guard !Task.isCancelled else { return }
        let result = uniqueItems(scanned).sorted { $0.size > $1.size }
        await MainActor.run {
            guard activeScanID == id, !isStoppingScan else { return }
            items = result
            totalSize = result.reduce(0) { $0 + $1.size }
            scannedItemCount = result.count
        }
    }

    /// Detail browsing never follows a symlink out of the configured Trash.
    func scanDirectory(_ url: URL) async -> [TrashItem] {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard CleanupFileSystem.contains(resolved, in: trashURL),
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              let contents = try? await listItems(url) else { return [] }
        var result: [TrashItem] = []
        for child in contents {
            guard !Task.isCancelled else { return [] }
            guard child.standardizedFileURL.deletingLastPathComponent() == url.standardizedFileURL else { continue }
            let size = await measureSize(child)
            let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey])
            result.append(TrashItem(url: child, name: child.lastPathComponent, size: size,
                dateDeleted: values?.contentModificationDate,
                isDirectory: values?.isDirectory == true && values?.isSymbolicLink != true))
        }
        return result.sorted { $0.size > $1.size }
    }

    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Permanent removal is limited to selected immediate children of the actual
    /// Trash root. Never remove the root, follow a parent symlink, or unlock files.
    @MainActor
    func emptyTrash() async -> Int64 {
        guard !isScanning, scanTask == nil, !isCleaning, !Task.isCancelled else { return 0 }
        isCleaning = true
        cleanedCount = 0
        cleanedSize = 0
        deletionFailures = []
        failedDeletionCount = 0
        cleaningWasStopped = false
        shouldStopCleaning = false
        diskSpaceChange = nil
        let selected = uniqueItems(items.filter(\.isSelected))
        let before = CleanupDiskSnapshot.capture(at: trashURL)
        var removed = Set<String>()
        defer {
            items.removeAll { removed.contains($0.url.standardizedFileURL.path) }
            totalSize = uniqueItems(items).reduce(0) { $0 + $1.size }
            scannedItemCount = items.count
            failedDeletionCount = deletionFailures.count
            diskSpaceChange = CleanupDiskSnapshot.capture(at: trashURL)?.change(since: before)
            isCleaning = false
            DiskSpaceManager.shared.updateDiskSpace()
        }
        for item in selected {
            if shouldStopCleaning || Task.isCancelled { cleaningWasStopped = true; break }
            do {
                guard isDirectTrashChild(item.url), isUnchangedTrashRoot() else {
                    throw NSError(domain: "MacOptimizer.TrashSafety", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: LocalizationManager.shared.text(
                            "仅允许删除废纸篓内选中的项目，已保留此路径。", "Only selected items inside Trash can be removed. This path was kept.")])
                }
                try await removeItem(item.url.standardizedFileURL)
                removed.insert(item.url.standardizedFileURL.path)
                cleanedCount += 1
                cleanedSize += item.size
            } catch {
                let failure = RemovalFailure(path: item.url, error: error)
                deletionFailures.append(failure)
                recordFailure(failure)
            }
            await Task.yield()
        }
        return cleanedSize
    }

    private func isDirectTrashChild(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL
        guard candidate.path != trashURL.path else { return false }
        return candidate.deletingLastPathComponent().path == trashURL.path
    }

    private func isUnchangedTrashRoot() -> Bool {
        guard trashURL.resolvingSymlinksInPath().path == trashURL.path,
              let attributes = try? fileManager.attributesOfItem(atPath: trashURL.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
    }

    private func uniqueItems(_ candidates: [TrashItem]) -> [TrashItem] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
    }

    @MainActor
    func reset() {
        guard !isScanning, scanTask == nil, !isCleaning else {
            stopScan()
            stopCleaning()
            return
        }
        items = []
        totalSize = 0
        needsPermission = false
        scannedItemCount = 0
        hasCompletedScan = false
        isStopped = false
        isStoppingScan = false
        currentScanPath = ""
        cleanedCount = 0
        cleanedSize = 0
        failedDeletionCount = 0
        cleaningWasStopped = false
        shouldStopCleaning = false
        deletionFailures = []
        scanFailure = nil
        diskSpaceChange = nil
    }
}

struct TrashView: View {
    // 使用共享的扫描服务管理器，防止切换界面时扫描中断
    @ObservedObject private var scanner = ScanServiceManager.shared.trashScanner
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var showEmptyConfirmation = false
    @State private var showCleaningFinished = false
    
    // 视图状态 (对应 ScanState)
    private var scanState: TrashScanState {
        if showCleaningFinished {
            return .finished
        } else if scanner.isCleaning {
            return .cleaning
        } else if scanner.isScanning {
            return .scanning
        } else if !scanner.items.isEmpty || scanner.isStopped {
            // 如果已经被停止，也显示结果页（可能是部分结果）
            return .completed
        } else if scanner.hasCompletedScan && scanner.items.isEmpty {
            return .clean
        }
        return .initial
    }
    
    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                NavigationStack {
                    content
                }
            } else {
                NavigationView {
                    content
                }
            }
        }
        .confirmationDialog(loc.L("empty_trash"), isPresented: $showEmptyConfirmation) {
            Button(loc.L("empty_trash"), role: .destructive) {
                Task {
                    _ = await scanner.emptyTrash()
                    showCleaningFinished = true
                }
            }
            Button(loc.L("cancel"), role: .cancel) {}
        } message: {
            Text(loc.text("此操作不可撤销，所有文件将被永久删除。", "This cannot be undone. All files will be permanently deleted."))
        }
    }
    
    private var content: some View {
        ZStack {
            switch scanState {
            case .initial:
                initialPage
            case .scanning:
                scanningPage
            case .completed:
                resultsPage
            case .clean:
                cleanPage
            case .cleaning:
                cleaningPage
            case .finished:
                finishedPage
            }
        }
    }
    
    // MARK: - 1. 初始页面
    private var initialPage: some View {
        ZStack {
            HStack(spacing: 60) {
                // Left Content
                VStack(alignment: .leading, spacing: 30) {
                    // Branding Header
                    HStack(spacing: 8) {
                        Text(loc.text("废纸篓清理", "Trash Cleanup"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        // Trash Icon
                        HStack(spacing: 4) {
                            Image(systemName: "trash.circle.fill")
                            Text(loc.text("全面清空", "Complete Empty"))
                                .font(.system(size: 20, weight: .heavy))
                        }
                        .foregroundColor(.white)
                    }
                    
                    Text(loc.text("倾倒 Mac 上所有废纸篓，包括邮件和照片图库垃圾。\n上次清空时间：从未", "Empty all Trash on Mac, including Mail and Photos.\nLast emptied: Never"))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .lineSpacing(4)
                    
                    // Feature Rows
                    VStack(alignment: .leading, spacing: 24) {
                        featureRow(
                            icon: "trash.slash",
                            title: loc.text("立即倾倒所有垃圾", "Empty All Trash Immediately"),
                            subtitle: loc.text("无需浏览所有驱动器和应用查找它们的废纸篓。", "No need to browse all drives and apps to find their trash.")
                        )
                        
                        featureRow(
                            icon: "exclamationmark.shield",
                            title: loc.text("避免访达错误", "Avoid Finder Errors"),
                            subtitle: loc.text("确保倾倒您的废纸篓，不管是否有任何问题。", "Ensures your Trash is emptied regardless of any issues.")
                        )
                        
                        featureRow(
                            icon: "mail.and.text.magnifyingglass",
                            title: loc.text("包含邮件和照片", "Include Mail & Photos"),
                            subtitle: loc.text("同时清理邮件应用和照片图库中的废纸篓。", "Also clean trash from Mail app and Photos library.")
                        )
                    }
                    
                    // Optional: View Items Button
                    Button(action: {}) {
                        Text(loc.text("查看详细项目...", "View Trash Items..."))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color(hex: "4DDEE8")) // Teal
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                .frame(maxWidth: 400)
                
                // Right Icon - Using feizhilou.png
                ZStack {
                    if let imagePath = Bundle.main.path(forResource: "feizhilou", ofType: "png"),
                       let nsImage = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 320, height: 320)
                            .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
                    } else {
                        // Fallback
                        RoundedRectangle(cornerRadius: 40)
                            .fill(LinearGradient(
                                colors: [Color(hex: "00D9A8"), Color(hex: "009688")],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 280, height: 280)
                            .overlay(
                                Image(systemName: "trash.circle.fill")
                                    .font(.system(size: 100))
                                    .foregroundColor(.white)
                            )
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
            
            // Bottom Floating Scan Button
            VStack {
                Spacer()
                Button(action: {
                    Task { await scanner.scan() }
                }) {
                    ZStack {
                        Circle()
                            .stroke(LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            ), lineWidth: 2)
                            .frame(width: 84, height: 84)
                        
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 74, height: 74)
                            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
                        
                        Text(loc.text(
    simplifiedChinese: "扫描",
    traditionalChinese: "掃描",
    english: "Scan",
    japanese: "スキャン",
    korean: "스캔",
    russian: "Сканировать"
))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, 40)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Feature Row Helper
    private func featureRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 2. 扫描中页面
    private var scanningPage: some View {
        VStack(spacing: 0) {
            // 顶部标题
            HStack {
                Text(loc.text("废纸篓", "Trash"))
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .padding(.top, 20)
            
            Spacer()
            
            // 中心动画图标 (Direct Image) -> Static Size enforcement
            ZStack {
                if let imagePath = Bundle.main.path(forResource: "feizhilou", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 280, height: 280)
                } else {
                     Image(systemName: "trash")
                        .font(.system(size: 100))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 280, height: 280) // Enforce frame container
            .padding(.bottom, 40)
            
            // 状态文字 - Use fixed frame to avoid layout jitter
            VStack(spacing: 8) {
                Text(loc.text("正在计算废纸篓文件夹的大小...", "Calculating Trash size..."))
                    .font(.title) 
                    .foregroundColor(.white)
                
                Text(scanner.currentScanPath) 
                    .font(.body)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: 20) // Fixed text height
                    .padding(.horizontal, 40)
                
                Text(loc.text("系统废纸篓", "System Trash"))
                    .font(.caption)
                    .foregroundColor(.secondaryText)
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
            
            // 停止按钮 (Bottom Center of Screen)
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.75) 
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                
                Button(action: {
                    scanner.stopScan()
                }) {
                    VStack(spacing: 2) {
                        Text(loc.text(
    simplifiedChinese: "停止",
    traditionalChinese: "停止",
    english: "Stop",
    japanese: "停止",
    korean: "정지",
    russian: "Остановить"
))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .frame(width: 70, height: 70)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Size below stop button
            Text(scanner.formattedTotalSize)
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
                .padding(.top, 10)
                .opacity(scanner.scannedItemCount > 0 ? 1 : 0) // Fade in instead of layout shift? Or just keep space
            
            Spacer()
                .frame(height: 60)
        }
    }
    
    // MARK: - 3. 扫描结果页面
    private var resultsPage: some View {
        VStack(spacing: 0) {
            // Top: Back Button
            HStack {
                Button(action: {
                    scanner.reset()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(loc.text("重新开始", "Start Over"))
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(loc.text("废纸篓", "Trash"))
                    .font(.title3)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Assistant placeholder
                 HStack {
                    Circle().fill(Color.white.opacity(0.2)).frame(width: 6, height: 6)
                    Text(loc.text(
    simplifiedChinese: "Mac 优化智能体",
    traditionalChinese: "Mac 最佳化智慧代理",
    english: "Mac Optimization Agent",
    japanese: "Mac最適化エージェント",
    korean: "Mac 최적화 에이전트",
    russian: "Агент оптимизации Mac"
))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .opacity(0.8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            // Main Content: Icon Left, Text Right
            HStack(spacing: 60) {
                // Large Icon Circle (Direct Image)
                if let imagePath = Bundle.main.path(forResource: "feizhilou", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 300, height: 300) // Large
                } else {
                     Image(systemName: "trash.fill")
                         .font(.system(size: 150))
                         .foregroundColor(.white)
                }
                
                // Text Info
                VStack(alignment: .leading, spacing: 16) {
                    Text(loc.text("扫描完毕", "Scan Complete"))
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(scanner.formattedTotalSize)
                            .font(.system(size: 60, weight: .light)) 
                            .foregroundColor(Color(hex: "60EFFF")) 
                        
                        Text(loc.L("smart_select"))
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc.text("包括", "Including"))
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                        
                        HStack(spacing: 8) {
                            Circle().fill(Color.white.opacity(0.6)).frame(width: 4, height: 4)
                            Text(loc.text("mac 上的废纸篓", "Trash on mac"))
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    // View Items Button
                    NavigationLink(destination: TrashDetailsSplitView(scanner: scanner)) {
                        Text(loc.L("view_items")) 
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    HStack {
                         Text(loc.text("共发现", "Total found"))
                         Text(scanner.formattedTotalSize)
                             .foregroundColor(.white)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                }
            }
            
            Spacer()
            
            // Clean Button (Floating circular, Bottom Center)
            ZStack {
                // Outer Glow Ring
                Circle()
                    .stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    .frame(width: 90, height: 90)
                
                Button(action: {
                     showEmptyConfirmation = true
                }) {
                    ZStack {
                        Circle()
                             .fill(Color.white.opacity(0.2))
                             .frame(width: 80, height: 80)
                        
                        Text(loc.text("倾倒", "Clean"))
                             .font(.system(size: 18, weight: .medium))
                             .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 60)
        }
    }
    
    // MARK: - 3.5. Clean Page
    private var cleanPage: some View {
        VStack(spacing: 0) {
            // Top Nav
            HStack {
                Button(action: {
                    scanner.reset()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(loc.text("重新开始", "Start Over"))
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(loc.L("trash"))
                    .font(.title2)
                    .foregroundColor(.white)
                
                Spacer()
                
                // Placeholder
                Text(loc.text("重新开始", "Start Over"))
                    .opacity(0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            // Central Icon (Using feizhilou.png)
            ZStack {
                if let imagePath = Bundle.main.path(forResource: "feizhilou", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 250)
                } else {
                     Image(systemName: "trash")
                        .font(.system(size: 80))
                        .foregroundColor(.white)
                }
                
                // Checkmark badge
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                    .background(Circle().fill(Color.white)) // White bg for checkmark to pop
                    .clipShape(Circle())
                    .offset(x: 60, y: 80)
            }
            .padding(.bottom, 30)

            // Text
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title)
                
                Text(loc.text("非常干净！", "Very Clean!"))
                    .font(.title)
                    .bold()
                    .foregroundColor(.white)
            }
            .padding(.bottom, 8)
            
            Text(loc.text("任何废纸篓中都没有文件。", "No files found in any Trash bin."))
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            // Back/Rescan Button
             CircularActionButton(
                 title: loc.text(
    simplifiedChinese: "返回",
    traditionalChinese: "返回",
    english: "Back",
    japanese: "戻る",
    korean: "뒤로",
    russian: "Назад"
),
                 gradient: CircularActionButton.blueGradient,
                 action: {
                     scanner.reset()
                 }
             )
             .padding(.bottom, 60)
        }
    }
    
    // MARK: - 4. 清理中页面
    private var cleaningPage: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.L("trash"))
                    .font(.title2)
                    .foregroundColor(.white)
            }
            .padding(.top, 20)
            
            Spacer()
            
            ZStack {
                Circle()
                    .fill(GradientStyles.trash.opacity(0.8))
                    .frame(width: 140, height: 140)
                
                Image(systemName: "trash")
                    .font(.system(size: 60))
                    .foregroundColor(.white)
                
                // 旋转圈
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(Double(scanner.cleanedCount * 20))) // 简单旋转
            }
            .padding(.bottom, 40)
            
            Text(loc.text("正在清理...", "Cleaning..."))
                .font(.title3)
                .foregroundColor(.white)
            
            Text(loc.text("已清理: \(scanner.cleanedCount) 个文件", "Cleaned: \(scanner.cleanedCount) items"))
                .foregroundColor(.secondaryText)
                .padding(.top, 8)
            
            Spacer()
            
            // 占位按钮
             CircularActionButton(
                 title: loc.text("清理中", "Cleaning"),
                 gradient: CircularActionButton.grayGradient,
                 action: {}
             )
             .disabled(true)
             .padding(.bottom, 60)
        }
    }
    
    // MARK: - 5. 清理完成页面
    private var finishedPage: some View {
        VStack(spacing: 0) {
            // 顶部导航
            HStack {
                Button(action: {
                    scanner.reset()
                    showCleaningFinished = false
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                        Text(loc.text(
    simplifiedChinese: "返回",
    traditionalChinese: "返回",
    english: "Back",
    japanese: "戻る",
    korean: "뒤로",
    russian: "Назад"
))
                    }
                    .foregroundColor(.secondaryText)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text(loc.L("trash"))
                    .font(.title2)
                    .foregroundColor(.white)
                
                Spacer()
                if #available(macOS 13.0, *) {
                    GridRow { Text("      ") } // Placeholder
                } else {
                    Text("      ")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.8)) // 成功绿
                    .frame(width: 160, height: 160)
                    .shadow(color: .green.opacity(0.4), radius: 20, x: 0, y: 10)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 40)
            
            Text(loc.text("清理完成", "Cleanup Complete"))
                .font(.title)
                .bold()
                .foregroundColor(.white)
            
            Text(loc.text("已永久删除 \(ByteCountFormatter.string(fromByteCount: scanner.cleanedSize, countStyle: .file)) 文件（逻辑大小）", "Permanently deleted \(ByteCountFormatter.string(fromByteCount: scanner.cleanedSize, countStyle: .file)) of files (logical size)"))
                .foregroundColor(.secondaryText)
                .padding(.top, 8)
            
            Spacer()
            
            // 完成按钮
             CircularActionButton(
                 title: loc.text(
    simplifiedChinese: "完成",
    traditionalChinese: "完成",
    english: "Done",
    japanese: "完了",
    korean: "완료",
    russian: "Готово"
),
                 gradient: CircularActionButton.blueGradient,
                 action: {
                     scanner.reset()
                     showCleaningFinished = false
                 }
             )
             .padding(.bottom, 60)
        }
    }
}

// 辅助视图：显示文件列表详情（保留之前的 TrashDirectoryView implementation）
// 虽然后续设计中可能不需要，但为了兼容性保留
struct TrashDirectoryView: View {
    let url: URL
    @State private var items: [TrashItem] = []
    @StateObject private var scanner = TrashScanner()
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        List {
            if items.isEmpty {
                Text(loc.text("空文件夹", "Empty Folder"))
                    .foregroundColor(.secondaryText)
                    .padding()
            } else {
                ForEach(items) { item in
                    itemRow(for: item)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowBackground(Color.clear)
                        .compatibleListRowSeparatorHidden()
                }
            }
        }
        .listStyle(.plain)
        .compatibleScrollContentBackgroundHidden()
        .background(Color.mainBackground)
        .navigationTitle(url.lastPathComponent)
        .task(id: url) {
            items = await scanner.scanDirectory(url)
        }
    }
    
    @ViewBuilder
    private func itemRow(for item: TrashItem) -> some View {
        Group {
            if item.isDirectory {
                NavigationLink(destination: TrashDirectoryView(url: item.url)) {
                    TrashItemRow(item: item)
                }
            } else {
                TrashItemRow(item: item)
            }
        }
        .scanResultContextMenu(
            isSelected: item.isSelected,
            displayName: item.name,
            url: item.url,
            onToggleSelection: {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].isSelected.toggle()
                }
            },
            onIgnore: { items.removeAll { $0.id == item.id } }
        )
    }
}

struct TrashItemRow: View {
    let item: TrashItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primaryText)
                    .lineLimit(1)
                
                Text("删除于 \(item.formattedDate)")
                    .font(.system(size: 11))
                    .foregroundColor(.tertiaryText)
            }
            
            Spacer()
            
            Text(item.formattedSize)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondaryText)
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

// TealMeshBackground removed - using global background from ContentView
