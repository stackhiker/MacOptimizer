
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Optimization Task Enum
enum OptimizerTask: String, CaseIterable, Identifiable {
    case networkOptimize     // 网络优化
    case bootOptimize        // 启动加速
    case memoryOptimize      // 内存优化
    case appAccelerate       // 应用加速
    case heavyConsumers      // 占用资源项目
    case launchAgents        // 启动代理
    case hungApps            // 挂起应用
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .networkOptimize: return "network"
        case .bootOptimize: return "bolt.fill"
        case .memoryOptimize: return "memorychip"
        case .appAccelerate: return "arrow.up.forward.app"
        case .heavyConsumers: return "chart.xyaxis.line"
        case .launchAgents: return "rocket.fill"
        case .hungApps: return "hourglass"
        }
    }
    
    var iconColor: Color {
        switch self {
        case .networkOptimize: return Color(red: 0.0, green: 0.6, blue: 1.0)  // Blue
        case .bootOptimize: return Color(red: 1.0, green: 0.8, blue: 0.0)     // Yellow
        case .memoryOptimize: return Color(red: 0.0, green: 0.8, blue: 0.6)   // Teal
        case .appAccelerate: return Color(red: 0.8, green: 0.2, blue: 0.8)    // Purple
        case .heavyConsumers: return Color(red: 1.0, green: 0.6, blue: 0.2)   // Orange
        case .launchAgents: return Color(red: 0.2, green: 0.8, blue: 0.4)     // Green
        case .hungApps: return Color(red: 0.9, green: 0.3, blue: 0.3)         // Red
        }
    }
    
    var englishTitle: String {
        switch self {
        case .networkOptimize: return "Network Optimization"
        case .bootOptimize: return "Speed Up Boot"
        case .memoryOptimize: return "Memory Optimization"
        case .appAccelerate: return "Old App Cache Files"
        case .heavyConsumers: return "Heavy Consumers"
        case .launchAgents: return "Launch Agents"
        case .hungApps: return "Hung Applications"
        }
    }
    
    var englishDescription: String {
        switch self {
        case .networkOptimize: return "Refresh DNS cache and report whether the system accepted the commands. Network settings are kept."
        case .bootOptimize: return "Disable unnecessary launch agents and login items to speed up Mac startup."
        case .memoryOptimize: return "Choose unneeded applications to quit normally, then inspect memory usage and pressure."
        case .appAccelerate: return "Move eligible app cache files untouched for 30 days to Trash. Running apps are skipped."
        case .heavyConsumers: return "Quit apps that are using too much processing power."
        case .launchAgents: return "Manage helper applications that launch automatically."
        case .hungApps: return "Request a normal quit; save dialogs and applications that remain running are respected."
        }
    }
    
    // Localized properties
    func title(for language: AppLanguage) -> String {
        let values: [AppLanguage: String]
        switch self {
        case .networkOptimize: values = [.chinese: "网络优化", .traditionalChinese: "網路最佳化", .english: "Network Optimization", .japanese: "ネットワーク最適化", .korean: "네트워크 최적화", .russian: "Оптимизация сети"]
        case .bootOptimize: values = [.chinese: "启动加速", .traditionalChinese: "啟動加速", .english: "Speed Up Boot", .japanese: "起動を高速化", .korean: "부팅 속도 향상", .russian: "Ускорение запуска"]
        case .memoryOptimize: values = [.chinese: "内存优化", .traditionalChinese: "記憶體最佳化", .english: "Memory Optimization", .japanese: "メモリ最適化", .korean: "메모리 최적화", .russian: "Оптимизация памяти"]
        case .appAccelerate: values = [.chinese: "清理旧应用缓存", .traditionalChinese: "清理舊應用程式快取", .english: "Old App Cache Files", .japanese: "古いアプリキャッシュ", .korean: "오래된 앱 캐시", .russian: "Старый кэш приложений"]
        case .heavyConsumers: values = [.chinese: "高资源占用应用", .traditionalChinese: "高資源佔用應用程式", .english: "Heavy Consumers", .japanese: "高負荷アプリ", .korean: "리소스 과다 사용 앱", .russian: "Ресурсоёмкие приложения"]
        case .launchAgents: values = [.chinese: "启动代理", .traditionalChinese: "啟動代理程式", .english: "Launch Agents", .japanese: "起動エージェント", .korean: "시작 에이전트", .russian: "Агенты запуска"]
        case .hungApps: values = [.chinese: "无响应的应用", .traditionalChinese: "無回應的應用程式", .english: "Hung Applications", .japanese: "応答しないアプリ", .korean: "응답하지 않는 앱", .russian: "Зависшие приложения"]
        }
        return values[language] ?? englishTitle
    }
    
    func description(for language: AppLanguage) -> String {
        if self == .appAccelerate { return language == .chinese ? "将 30 天未修改且未访问的旧缓存文件移到废纸篓，跳过运行中的应用。" : englishDescription }
        if self == .hungApps { return language == .chinese ? "请求正常退出，保留保存对话框和仍在运行的应用。" : englishDescription }
        if self == .networkOptimize { return language == .chinese ? "刷新 DNS 缓存并报告实际结果，保留网络设置。" : englishDescription }
        let values: [AppLanguage: String]
        switch self {
        case .networkOptimize: values = [.chinese: "刷新 DNS 与网络缓存，帮助解决连接和域名解析问题。", .traditionalChinese: "重新整理 DNS 與網路快取，協助解決連線和網域解析問題。", .english: englishDescription, .japanese: "DNSとネットワークキャッシュを更新し、接続や名前解決の問題を改善します。", .korean: "DNS 및 네트워크 캐시를 새로 고쳐 연결과 도메인 확인 문제를 해결합니다.", .russian: "Обновляет кэш DNS и сети, помогая устранить проблемы подключения и разрешения имён."]
        case .bootOptimize: values = [.chinese: "管理不必要的启动代理和登录项，加快 Mac 启动速度。", .traditionalChinese: "管理不必要的啟動代理程式和登入項目，加快 Mac 啟動速度。", .english: englishDescription, .japanese: "不要な起動エージェントとログイン項目を管理し、Macの起動を高速化します。", .korean: "불필요한 시작 에이전트와 로그인 항목을 관리하여 Mac 부팅 속도를 높입니다.", .russian: "Управляет ненужными агентами запуска и объектами входа, ускоряя запуск Mac."]
        case .memoryOptimize: values = [.chinese: "选择不需要的应用并正常退出，查看内存占用和压力变化。", .traditionalChinese: "釋放記憶體並減少背景佔用，提升系統回應速度。", .english: englishDescription, .japanese: "メモリを解放してバックグラウンドの使用量を減らし、応答性を向上させます。", .korean: "메모리를 확보하고 백그라운드 사용량을 줄여 시스템 반응 속도를 높입니다.", .russian: "Освобождает память и снижает фоновую нагрузку, повышая отзывчивость системы."]
        case .appAccelerate: values = [.chinese: "清理应用缓存并优化数据，让应用启动更快。", .traditionalChinese: "清理應用程式快取並最佳化資料，讓應用程式啟動更快。", .english: englishDescription, .japanese: "アプリのキャッシュとデータを最適化し、起動を高速化します。", .korean: "앱 캐시와 데이터를 최적화하여 앱을 더 빠르게 실행합니다.", .russian: "Оптимизирует кэш и данные приложений, ускоряя их запуск."]
        case .heavyConsumers: values = [.chinese: "找出占用过多处理器或内存的应用，并在不需要时将其关闭。", .traditionalChinese: "找出佔用過多處理器或記憶體的應用程式，並在不需要時將其關閉。", .english: englishDescription, .japanese: "CPUやメモリを大量に使用するアプリを見つけ、不要な場合は終了します。", .korean: "CPU 또는 메모리를 과도하게 사용하는 앱을 찾아 필요하지 않을 때 종료합니다.", .russian: "Находит приложения с высокой нагрузкой на процессор или память и позволяет завершить ненужные."]
        case .launchAgents: values = [.chinese: "管理随应用自动启动的辅助程序。", .traditionalChinese: "管理隨應用程式自動啟動的輔助程式。", .english: englishDescription, .japanese: "アプリとともに自動起動する補助プログラムを管理します。", .korean: "앱과 함께 자동으로 실행되는 도우미 프로그램을 관리합니다.", .russian: "Управляет вспомогательными программами, запускаемыми автоматически."]
        case .hungApps: values = [.chinese: "强制退出无响应的应用以释放系统资源。", .traditionalChinese: "強制結束無回應的應用程式以釋放系統資源。", .english: englishDescription, .japanese: "応答しないアプリを強制終了してシステムリソースを解放します。", .korean: "응답하지 않는 앱을 강제 종료하여 시스템 리소스를 확보합니다.", .russian: "Принудительно завершает зависшие приложения, освобождая ресурсы системы."]
        }
        return values[language] ?? englishDescription
    }
    
    // 是否为一键优化（点击即执行）
    var isOneClickOptimize: Bool {
        switch self {
        case .networkOptimize, .bootOptimize, .memoryOptimize, .appAccelerate:
            return true
        default:
            return false
        }
    }
}

// MARK: - Data Models
struct OptimizerProcessItem: Identifiable, Equatable {
    let id: Int32 // PID
    let name: String
    let icon: NSImage
    let usageDescription: String // e.g. "15% CPU" or "500 MB"
    var isSelected: Bool = false
    var bundleIdentifier: String? = nil
}

struct LaunchAgentItem: Identifiable, Equatable {
    let id = UUID()
    let path: String
    let name: String // Extracted from filename or Label
    let label: String
    let icon: NSImage
    var isEnabled: Bool // Status
    var isSelected: Bool = false
}

// MARK: - Service
class OptimizerService: ObservableObject {
    static let shared = OptimizerService()

    @Published var selectedTask: OptimizerTask = .heavyConsumers
    @Published var selectedTasks: Set<OptimizerTask> = []
    @Published var heavyProcesses: [OptimizerProcessItem] = []
    @Published var launchAgents: [LaunchAgentItem] = []
    @Published var hungApps: [OptimizerProcessItem] = []
    @Published var isScanning = false
    @Published var isExecuting = false
    @Published private(set) var executionWasCancelled = false
    
    // 执行进度跟踪
    @Published var executingTask: OptimizerTask? = nil
    @Published var completedTasks: Set<OptimizerTask> = []
    @Published var executionProgress: Double = 0.0
    @Published var showResults = false
    
    // 内存优化 - 高内存应用列表
    @Published var highMemoryApps: [OptimizerProcessItem] = []
    @Published var showMemoryConfirmAlert = false
    @Published var memoryAlertIgnored = false
    @Published private(set) var memoryConfirmation: MemoryConfirmation = .pending
    @Published var taskMessages: [OptimizerTask: String] = [:]
    @Published var failedTasks: Set<OptimizerTask> = []
    
    // 启动加速 - 启动项列表
    @Published var bootAgentsToDisable: [LaunchAgentItem] = []
    @Published var showBootConfirmAlert = false
    @Published var bootAlertIgnored = false
    private var bootTaskSucceeded = false
    private let taskExecutor: (@MainActor (OptimizerTask) async -> Bool)?

    init(taskExecutor: (@MainActor (OptimizerTask) async -> Bool)? = nil) {
        self.taskExecutor = taskExecutor
    }
    
    func toggleTaskSelection(_ task: OptimizerTask) {
        if selectedTasks.contains(task) {
            selectedTasks.remove(task)
        } else {
            selectedTasks.insert(task)
        }
    }
    
    func selectAllTasks() {
        selectedTasks = Set(OptimizerTask.allCases)
    }
    
    func deselectAllTasks() {
        selectedTasks.removeAll()
    }
    
    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            await fetchHeavyConsumers()
            await fetchLaunchAgents()
            await fetchHungApps()
            await MainActor.run { self.isScanning = false }
        }
    }

    func scanAndWait() async {
        scan()
        while isScanning {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
    }
    
    // 批量执行所有选中的任务
    @MainActor
    func executeAllSelectedTasks() async {
        guard !isExecuting, !Task.isCancelled else { return }
        isExecuting = true
        executionWasCancelled = false
        completedTasks.removeAll()
        failedTasks.removeAll()
        taskMessages.removeAll()
        executionProgress = 0
        showResults = false
        memoryConfirmation = .pending
        memoryAlertIgnored = false
        showMemoryConfirmAlert = false
        bootAlertIgnored = false
        bootTaskSucceeded = false
        showBootConfirmAlert = false
        defer {
            if Task.isCancelled { executionWasCancelled = true; showResults = false }
            executingTask = nil
            showMemoryConfirmAlert = false
            showBootConfirmAlert = false
            isExecuting = false
        }
        
        let tasksToExecute = Array(selectedTasks).sorted { $0.rawValue < $1.rawValue }
        let totalTasks = tasksToExecute.count
        
        for (index, task) in tasksToExecute.enumerated() {
            if executionWasCancelled || Task.isCancelled { break }
            await MainActor.run {
                executingTask = task
                executionProgress = Double(index) / Double(totalTasks)
            }
            
            let succeeded = await executeTask(task)

            if executionWasCancelled || Task.isCancelled { break }
            
            await MainActor.run {
                if succeeded { _ = completedTasks.insert(task) }
                else { _ = failedTasks.insert(task) }
            }
        }
        
        await MainActor.run {
            executingTask = nil
            if executionWasCancelled || Task.isCancelled {
                showResults = false
            } else {
                executionProgress = 1.0
                showResults = true
            }
        }
    }

    @MainActor
    func cancelExecution() {
        guard isExecuting else { return }
        executionWasCancelled = true
        memoryConfirmation = .cancelled
        showMemoryConfirmAlert = false
        showBootConfirmAlert = false
    }

    @MainActor
    func confirmMemoryApplications() {
        guard showMemoryConfirmAlert, !executionWasCancelled else { return }
        memoryConfirmation = .confirmed
        showMemoryConfirmAlert = false
    }

    @MainActor
    func cancelMemoryApplications() {
        memoryAlertIgnored = true
        memoryConfirmation = .cancelled
        showMemoryConfirmAlert = false
    }
    
    // 执行单个任务
    private func executeTask(_ task: OptimizerTask) async -> Bool {
        if let taskExecutor { return await taskExecutor(task) }
        switch task {
        case .networkOptimize:
            return await performNetworkOptimization()
        case .bootOptimize:
            return await performBootOptimization()
        case .memoryOptimize:
            return await performMemoryOptimization()
        case .appAccelerate:
            return await performAppAcceleration()
        case .heavyConsumers:
            return await cleanupHeavyConsumers()
        case .launchAgents:
            return await cleanupLaunchAgents()
        case .hungApps:
            return await cleanupHungApps()
        }
        
    }
    
    @MainActor
    private func fetchHeavyConsumers() {
        // Run ps command to get top CPU consumers
        // ps -Aceo pid,%cpu,comm -r | head -n 10
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "ps -Aceo pid,%cpu,comm -r | head -n 15"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            var items: [OptimizerProcessItem] = []
            let lines = output.components(separatedBy: .newlines).dropFirst() // Skip header
            
            for line in lines {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 3, let pid = Int32(parts[0]), let cpu = Double(parts[1]) {
                    if cpu > 1.0 { // Filter apps using > 1% CPU (simulated threshold for "Heavy")
                         // Get app name and icon
                        if let app = NSRunningApplication(processIdentifier: pid) {
                            // Exclude self
                            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier || app.activationPolicy != .regular || app.bundleIdentifier == "com.apple.finder" { continue }
                            
                            // Only show apps with icons (user visible)
                            if let icon = app.icon, let name = app.localizedName {
                                items.append(OptimizerProcessItem(id: pid, name: name, icon: icon, usageDescription: String(format: "%.1f%% CPU", cpu), bundleIdentifier: app.bundleIdentifier))
                            }
                        }
                    }
                }
            }
            self.heavyProcesses = items
        }
    }
    
    @MainActor
    private func fetchLaunchAgents() {
        var items: [LaunchAgentItem] = []
        let paths = [
            FileManager.default.homeDirectoryForCurrentUser.path + "/Library/LaunchAgents",
            "/Library/LaunchAgents"
        ]
        
        for path in paths {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
                for file in files where file.hasSuffix(".plist") {
                    let fullPath = path + "/" + file
                    // Simplified: Use filename as name, generic icon
                    let name = file.replacingOccurrences(of: ".plist", with: "")
                    // Check if loaded? roughly assume enabled if file exists for now, 
                    // real check involves `launchctl list`
                    
                    // Simple logic: existing plist = enabled (unless disabled in override database, which is complex)
                    // We will just list them.
                    items.append(LaunchAgentItem(
                        path: fullPath,
                        name: name,
                        label: name,
                        icon: NSWorkspace.shared.icon(for: UTType(filenameExtension: "plist") ?? .propertyList),
                        isEnabled: true
                    ))
                }
            }
        }
        self.launchAgents = items
    }
    
    @MainActor
    private func fetchHungApps() {
        // Detect apps in Uninterruptible sleep (U) or Zombie (Z) state
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "ps -Aceo pid,state,comm | grep -e 'U' -e 'Z'"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
             var items: [OptimizerProcessItem] = []
             let lines = output.components(separatedBy: .newlines)
             for line in lines {
                 let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                 if parts.count >= 3, (parts[1].contains("U") || parts[1].contains("Z")), let pid = Int32(parts[0]) {
                     // Check if it's a gui app
                     if let app = NSRunningApplication(processIdentifier: pid), let icon = app.icon, let name = app.localizedName {
                         if app.processIdentifier == ProcessInfo.processInfo.processIdentifier || app.activationPolicy != .regular || app.bundleIdentifier == "com.apple.finder" { continue } // Exclude self and system applications
                         let state = parts[1]
                         let desc = state.contains("Z") ? "Zombie" : "Unresponsive"
                         items.append(OptimizerProcessItem(id: pid, name: name, icon: icon, usageDescription: desc, bundleIdentifier: app.bundleIdentifier))
                     }
                 }
             }
             self.hungApps = items
        }
    }
    
    // MARK: - 清理任务执行
    
    private func cleanupHeavyConsumers() async -> Bool {
        let items = await MainActor.run { heavyProcesses.filter { $0.isSelected } }
        let result = await quitApplications(items, for: .heavyConsumers)
        await fetchHeavyConsumers()
        return result
    }

    private func cleanupLaunchAgents() async -> Bool {
        let items = await MainActor.run { launchAgents.filter { $0.isSelected } }
        var failures: [String] = []
        var completed = 0
        for item in items {
            if executionWasCancelled || Task.isCancelled { break }
            let result = runCheckedMaintenanceCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", item.path])
            if result.success { completed += 1 } else { failures.append(item.name + ": " + result.output) }
            await Task.yield()
        }
        let loc = LocalizationManager.shared
        let finalFailures = failures
        let finalCompleted = completed
        await MainActor.run {
            taskMessages[.launchAgents] = loc.text("已停止 \(finalCompleted) 个启动代理。", "Stopped \(finalCompleted) launch agents.")
            if !finalFailures.isEmpty { taskMessages[.launchAgents, default: ""] += "\n" + finalFailures.joined(separator: "\n") }
        }
        await fetchLaunchAgents()
        return failures.isEmpty && completed == items.count && !executionWasCancelled && !Task.isCancelled
    }

    private func cleanupHungApps() async -> Bool {
        let items = await MainActor.run { hungApps.filter { $0.isSelected } }
        let result = await quitApplications(items, for: .hungApps)
        await fetchHungApps()
        return result
    }

    @MainActor
    private func quitApplications(_ items: [OptimizerProcessItem], for task: OptimizerTask) async -> Bool {
        let loc = LocalizationManager.shared
        var exited = 0
        var retained: [String] = []
        for item in items {
            if executionWasCancelled || Task.isCancelled { break }
            guard let app = NSRunningApplication(processIdentifier: item.id) else {
                exited += 1
                continue
            }
            guard app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.bundleIdentifier != "com.apple.finder",
                  app.bundleIdentifier == item.bundleIdentifier else {
                retained.append(item.name)
                continue
            }
            let result = await requestGracefulTermination(request: { app.terminate() }, hasExited: { app.isTerminated },
                                                          isCancelled: { self.executionWasCancelled || Task.isCancelled })
            if result == .exited { exited += 1 } else { retained.append(item.name) }
        }
        var message = loc.text("已退出 \(exited) 个应用。", "Quit \(exited) applications.")
        if !retained.isEmpty {
            message += loc.text("仍在运行：", " Still running: ") + retained.joined(separator: ", ")
            message += loc.text("。请先保存工作并手动退出。", ". Save your work and quit them manually.")
        }
        taskMessages[task] = message
        return retained.isEmpty && !executionWasCancelled && !Task.isCancelled
    }

    // MARK: - 网络优化
    private func performNetworkOptimization() async -> Bool {
        let loc = LocalizationManager.shared
        let flush = runCheckedMaintenanceCommand("/usr/bin/dscacheutil", ["-flushcache"])
        let responder = runCheckedMaintenanceCommand("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        let success = flush.success && responder.success
        await MainActor.run {
            taskMessages[.networkOptimize] = success
                ? loc.text("DNS 缓存已刷新。网络设置已保留。", "DNS cache refreshed. Network settings were kept.")
                : loc.text("DNS 刷新未完成：", "DNS refresh incomplete: ") + [flush.output, responder.output].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        return success
    }

    // MARK: - 启动加速
    private func performBootOptimization() async -> Bool {
        await scanBootAgents()
        await MainActor.run {
            bootAlertIgnored = false
            bootTaskSucceeded = bootAgentsToDisable.isEmpty
            showBootConfirmAlert = !bootAgentsToDisable.isEmpty
        }
        while showBootConfirmAlert && !executionWasCancelled && !Task.isCancelled {
            do { try await Task.sleep(nanoseconds: 100_000_000) }
            catch { return false }
        }
        return bootTaskSucceeded && !executionWasCancelled && !Task.isCancelled
    }

    // 扫描启动代理
    @MainActor
    private func scanBootAgents() {
        bootAgentsToDisable.removeAll()
        
        let userAgentsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        
        // 安全白名单 - 这些不应该被禁用
        let safeAgents = ["com.apple.", "homebrew.", "com.github."]
        
        // 已知的可以安全禁用的常见启动代理（通常是自动更新程序）
        let knownNonEssential = [
            "update", "updater", "helper", "assistant", "agent",
            "sync", "backup", "cloud", "autoupdate"
        ]
        
        guard let agents = try? FileManager.default.contentsOfDirectory(atPath: userAgentsPath.path) else {
            return
        }
        
        for agent in agents where agent.hasSuffix(".plist") {
            let agentLower = agent.lowercased()
            
            // 跳过白名单中的代理
            if safeAgents.contains(where: { agentLower.contains($0) }) {
                continue
            }
            
            // 检查是否是已知的非必需启动项
            let isNonEssential = knownNonEssential.contains { agentLower.contains($0) }
            
            let agentPath = userAgentsPath.appendingPathComponent(agent)
            let name = agent.replacingOccurrences(of: ".plist", with: "")
            
            // 尝试从 plist 中读取 Label
            var label = name
            if let plistData = try? Data(contentsOf: agentPath),
               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
               let plistLabel = plist["Label"] as? String {
                label = plistLabel
            }
            
            // 检查是否已启用
            let isEnabled = agent.hasSuffix(".plist") // 简化判断
            
            bootAgentsToDisable.append(LaunchAgentItem(
                path: agentPath.path,
                name: name,
                label: label,
                icon: NSWorkspace.shared.icon(for: .propertyList),
                isEnabled: isEnabled,
                isSelected: isNonEssential // 默认选中非必需项
            ))
        }
        
        // 按名称排序
        bootAgentsToDisable.sort { $0.name < $1.name }
    }
    
    // 禁用选中的启动代理
    func disableSelectedBootAgents() async {
        guard !executionWasCancelled else { return }
        let items = await MainActor.run { bootAgentsToDisable.filter { $0.isSelected } }
        var failures: [String] = []
        var completed = 0
        for item in items {
            if executionWasCancelled || Task.isCancelled { break }
            let unload = runCheckedMaintenanceCommand("/bin/launchctl", ["unload", "-w", item.path])
            guard unload.success else { failures.append(item.name + ": " + unload.output); continue }
            do {
                try FileManager.default.moveItem(atPath: item.path, toPath: item.path + ".disabled")
                completed += 1
            } catch { failures.append(item.name + ": " + error.localizedDescription) }
        }
        let loc = LocalizationManager.shared
        let finalFailures = failures
        let finalCompleted = completed
        await MainActor.run {
            bootTaskSucceeded = !items.isEmpty && finalFailures.isEmpty && finalCompleted == items.count
            taskMessages[.bootOptimize] = loc.text("已禁用 \(finalCompleted) 个启动代理。", "Disabled \(finalCompleted) launch agents.")
            if !finalFailures.isEmpty { taskMessages[.bootOptimize, default: ""] += "\n" + finalFailures.joined(separator: "\n") }
            bootAgentsToDisable.removeAll()
            showBootConfirmAlert = false
        }
    }

    // MARK: - 内存优化
    private func performMemoryOptimization() async -> Bool {
        let loc = LocalizationManager.shared
        guard await detectHighMemoryApps() else { return false }
        await MainActor.run {
            memoryAlertIgnored = false
            memoryConfirmation = .pending
            showMemoryConfirmAlert = !highMemoryApps.isEmpty
        }
        if highMemoryApps.isEmpty {
            await MainActor.run {
                taskMessages[.memoryOptimize] = loc.text("未发现需要退出的高内存应用。", "No high-memory applications to quit.")
            }
            return MemorySnapshot.read() != nil
        }
        // Closing the sheet or stopping the task is cancellation. Waiting is never approval.
        let approved = await awaitExplicitMemoryConfirmation(
            isPresented: { self.showMemoryConfirmAlert }, decision: { self.memoryConfirmation },
            isCancelled: { self.executionWasCancelled || Task.isCancelled })
        guard approved, !Task.isCancelled else {
            await MainActor.run { taskMessages[.memoryOptimize] = loc.text("已跳过退出应用。", "Skipped quitting applications.") }
            return false
        }
        let items = await MainActor.run { highMemoryApps.filter { $0.isSelected } }
        guard !items.isEmpty else {
            await MainActor.run { taskMessages[.memoryOptimize] = loc.text("未选择应用，未执行退出。", "No applications selected; none were quit.") }
            return false
        }
        let before = MemorySnapshot.read()
        let result = await quitApplications(items, for: .memoryOptimize)
        if let before, let after = MemorySnapshot.read() {
            let change = Int64(after.usedBytes) - Int64(before.usedBytes)
            let amount = ByteCountFormatter.string(fromByteCount: abs(change), countStyle: .memory)
            await MainActor.run {
                taskMessages[.memoryOptimize, default: ""] += change <= 0
                    ? loc.text(" 内存占用观测下降 \(amount)。", " Observed memory use decreased by \(amount).")
                    : loc.text(" 内存占用观测上升 \(amount)。", " Observed memory use increased by \(amount).")
                taskMessages[.memoryOptimize, default: ""] += loc.text(" 当前压力：", " Current pressure: ") + after.pressure.title(loc)
            }
        }
        await MainActor.run { highMemoryApps.removeAll() }
        return result
    }

    // 检测高内存应用
    @MainActor
    private func detectHighMemoryApps() -> Bool {
        highMemoryApps.removeAll()
        let result = runCheckedMaintenanceCommand("/bin/ps", ["-axo", "pid=,rss="])
        guard result.success else {
            taskMessages[.memoryOptimize] = LocalizationManager.shared.text("无法读取应用内存：", "Cannot read application memory: ") + result.output
            return false
        }
        var candidates: [(app: NSRunningApplication, rss: Double)] = []
        for line in result.output.components(separatedBy: .newlines) {
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 2, let pid = Int32(parts[0]), let rss = Double(parts[1]), rss > 500_000,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  pid != ProcessInfo.processInfo.processIdentifier,
                  let bundleID = app.bundleIdentifier, bundleID != "com.apple.finder",
                  app.icon != nil, app.localizedName != nil else { continue }
            candidates.append((app, rss))
        }
        highMemoryApps = candidates.sorted { $0.rss > $1.rss }.compactMap { candidate in
            guard let name = candidate.app.localizedName, let icon = candidate.app.icon else { return nil }
            return OptimizerProcessItem(id: candidate.app.processIdentifier, name: name, icon: icon,
                usageDescription: ByteCountFormatter.string(fromByteCount: Int64(candidate.rss * 1024), countStyle: .memory),
                bundleIdentifier: candidate.app.bundleIdentifier)
        }
        return true
    }

    // MARK: - 应用加速
    private func performAppAcceleration() async -> Bool {
        let loc = LocalizationManager.shared
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        let cleaner = MaintenanceFileCleaner(isOwnerRunning: { owner in
            NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == owner }
        })
        let result = cleaner.clean(root: root, kind: .cache, isCancelled: { self.executionWasCancelled || Task.isCancelled })
        await MainActor.run {
            taskMessages[.appAccelerate] = loc.text("已将 \(result.movedCount) 个旧缓存文件移到废纸篓；清空后才会释放磁盘空间。", "Moved \(result.movedCount) old cache files to Trash; empty it later to release disk space.")
            if !result.failures.isEmpty { taskMessages[.appAccelerate, default: ""] += "\n" + result.failures.joined(separator: "\n") }
        }
        return result.failures.isEmpty && !result.cancelled
    }

    func toggleSelection(for id: Any) {
        // Helper to toggle (kept for compatibility)
    }
}

// MARK: - Views
struct OptimizerView: View {
    @ObservedObject private var service = OptimizerService.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    @State private var viewState = 0 // 0: Landing, 1: List, 2: Executing, 3: Results
    
    var body: some View {
        ZStack {
             // Shared Background
            BackgroundStyles.privacy.ignoresSafeArea()
            
            switch viewState {
            case 0:
                OptimizerLandingView(viewState: $viewState, loc: loc)
            case 1:
                optimizerListView
            case 2:
                executingView
            case 3:
                resultsView
            default:
                optimizerListView
            }
        }
        .onAppear {
            service.scan()
            viewState = 0
        }
        .onChange(of: service.showResults) { showResults in
            if showResults {
                viewState = 3
            }
        }
        .sheet(isPresented: $service.showMemoryConfirmAlert) {
            MemoryConfirmationDialog(service: service, loc: loc)
        }
        .sheet(isPresented: $service.showBootConfirmAlert) {
            BootOptimizationDialog(service: service, loc: loc)
        }
    }
    
    // Existing list logic moved here
    var optimizerListView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                // LEFT PANEL (Task Selection)
                ZStack {
                    // Transparent to let shared background show through
                    VStack(alignment: .leading, spacing: 0) {
                         // Back button (Functional)
                        Button(action: { viewState = 0 }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text(loc.text(
    simplifiedChinese: "简介",
    traditionalChinese: "簡介",
    english: "Intro",
    japanese: "イントロ",
    korean: "Intro",
    russian: "Вводная"
))
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                        
                        // Tasks List (支持多选)
                        ScrollView {
                            VStack(spacing: 4) {
                                ForEach(OptimizerTask.allCases) { task in
                                    OptimizerTaskRow(
                                        task: task,
                                        isSelected: service.selectedTasks.contains(task),
                                        isActive: service.selectedTask == task,
                                        isMultiSelect: true,
                                        loc: loc
                                    )
                                    .onTapGesture {
                                        service.toggleTaskSelection(task)
                                        service.selectedTask = task
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .frame(width: geometry.size.width * 0.4)
                
                // RIGHT PANEL (Details)
                ZStack {
                    // Background handled in parent ZStack
                    
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            Text(loc.text("优化", "Optimization"))
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                            Spacer()
                            
                            // Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.5))
                                Text(loc.text(
    simplifiedChinese: "搜索",
    traditionalChinese: "搜尋",
    english: "Search",
    japanese: "検索する",
    korean: "검색",
    russian: "Поиск"
))
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.3))
                                Spacer()
                            }
                            .frame(width: 120, height: 22)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(4)
                            

                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 14)
                        
                        // Title & Desc
                        VStack(alignment: .leading, spacing: 6) {
                            Text(service.selectedTask.title(for: loc.currentLanguage))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(service.selectedTask.description(for: loc.currentLanguage))
                                .font(.system(size: 11))
                                .lineSpacing(3)
                                .foregroundColor(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        
                        // Content List
                        ScrollView {
                            VStack(spacing: 0) {
                                // 一键优化任务 - 显示功能说明
                                if service.selectedTask.isOneClickOptimize {
                                    VStack(spacing: 20) {
                                        // 功能图标
                                        ZStack {
                                            Circle()
                                                .fill(service.selectedTask.iconColor.opacity(0.2))
                                                .frame(width: 80, height: 80)
                                            Image(systemName: service.selectedTask.icon)
                                                .font(.system(size: 36))
                                                .foregroundColor(service.selectedTask.iconColor)
                                        }
                                        .padding(.top, 30)
                                        
                                        // 提示信息
                                        VStack(spacing: 8) {
                                            Text(loc.text("点击下方按钮开始优化", "Click button below to start optimization"))
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.white.opacity(0.7))
                                            
                                            Text(loc.text("此操作是安全的，可随时执行", "This operation is safe and can be run anytime"))
                                                .font(.system(size: 12))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                } else if service.selectedTask == .heavyConsumers {
                                    ForEach($service.heavyProcesses) { $proc in
                                        HeavyProcessRow(item: proc, isSelected: $proc.isSelected)
                                    }
                                } else if service.selectedTask == .launchAgents {
                                    ForEach($service.launchAgents) { $agent in
                                        LaunchAgentRow(item: agent, isSelected: $agent.isSelected, loc: loc)
                                    }
                                } else if service.selectedTask == .hungApps {
                                    if service.hungApps.isEmpty {
                                        Text(loc.text("未发现挂起的应用程序", "No hung applications found"))
                                            .foregroundColor(.white.opacity(0.5))
                                            .padding(.top, 40)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    } else {
                                        ForEach($service.hungApps) { $proc in
                                            HeavyProcessRow(item: proc, isSelected: $proc.isSelected)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        Spacer()
                        
                        // Execute Button - 执行所有选中的任务

                    }
                    .frame(width: geometry.size.width * 0.6)
                }
            }
            
            Button(action: {
                viewState = 2
                Task {
                    await service.executeAllSelectedTasks()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .strokeBorder(
                            LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                        .frame(width: 60, height: 60)
                    
                    if service.isExecuting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(loc.text("执行", "Run"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(service.isExecuting || service.selectedTasks.isEmpty)
            .padding(.bottom, 40)
        }
    }
}
    
    // MARK: - 执行视图
    var executingView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // 标题
            Text(loc.text("正在执行优化任务...", "Executing Optimization Tasks..."))
                .font(.title2)
                .foregroundColor(.white)
            
            // 任务列表进度
            VStack(spacing: 12) {
                ForEach(Array(service.selectedTasks).sorted { $0.rawValue < $1.rawValue }) { task in
                    HStack(spacing: 12) {
                        // 状态图标
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(task.iconColor)
                                .frame(width: 28, height: 28)
                            
                            Image(systemName: task.icon)
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                        
                        // 任务名称
                        Text(task.title(for: loc.currentLanguage))
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // 状态
                        if service.completedTasks.contains(task) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if service.executingTask == task {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(service.executingTask == task ? Color.white.opacity(0.1) : Color.clear)
                    .cornerRadius(8)
                }
            }
            .frame(maxWidth: 400)
            .padding(.horizontal, 40)
            
            // 进度文本
            Text("\(service.completedTasks.count) / \(service.selectedTasks.count)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
        }
    }
    
    // MARK: - 结果视图
    var resultsView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // 完成图标
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(.green)
            }
            
            Text(loc.text("优化完成！", "Optimization Complete!"))
                .font(.title)
                .bold()
                .foregroundColor(.white)
            
            // 完成的任务列表
            VStack(spacing: 8) {
                ForEach(Array(service.completedTasks).sorted { $0.rawValue < $1.rawValue }) { task in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(task.iconColor)
                                .frame(width: 22, height: 22)
                            
                            Image(systemName: task.icon)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                        }
                        
                        Text(task.title(for: loc.currentLanguage))
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            .frame(maxWidth: 350)
            .padding(16)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            
            Spacer()
            
            // 返回按钮
            Button(action: {
                service.showResults = false
                service.completedTasks.removeAll()
                viewState = 1
            }) {
                Text(loc.text(
    simplifiedChinese: "完成",
    traditionalChinese: "完成",
    english: "Done",
    japanese: "完了",
    korean: "완료",
    russian: "Готово"
))
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 50)
        }
    }
}

// MARK: - Row Components
struct OptimizerTaskRow: View {
    let task: OptimizerTask
    let isSelected: Bool
    let isActive: Bool
    var isMultiSelect: Bool = false
    @ObservedObject var loc: LocalizationManager
    
    var body: some View {
        HStack(spacing: 8) {
            // Checkbox (多选) 或 Radio Button (单选)
            if isMultiSelect {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(isSelected ? Color.green : Color.white.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isSelected ? Color.green : Color.clear)
                        )
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            } else {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(task.iconColor)
                    .frame(width: 24, height: 24)
                
                Image(systemName: task.icon)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
            }
            
            // Title
            Text(task.title(for: loc.currentLanguage))
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.black.opacity(0.2) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}

struct HeavyProcessRow: View {
    let item: OptimizerProcessItem
    @Binding var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Checkbox - 绿色勾选样式
            Button(action: { isSelected.toggle() }) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.green : Color.white.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 24, height: 24)
            
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
            
            Spacer()
            
            Text(item.usageDescription)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.1))
                .cornerRadius(3)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }
}

struct LaunchAgentRow: View {
    let item: LaunchAgentItem
    @Binding var isSelected: Bool
    @ObservedObject var loc: LocalizationManager
    
    var body: some View {
        HStack(spacing: 8) {
            // Checkbox - 绿色勾选样式
            Button(action: { isSelected.toggle() }) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.green : Color.white.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 16, height: 16)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 24, height: 24)
            
            Text(item.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            // Status Indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(item.isEnabled ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text(item.isEnabled ? (loc.text("已启用", "Enabled")) : (loc.text("已禁用", "Disabled")))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }
}
// MARK: - Landing Components
struct OptimizerLandingView: View {
    @Binding var viewState: Int // 0=Landing, 1=List
    @ObservedObject var loc: LocalizationManager
    
    var body: some View {
        ZStack {
            HStack(spacing: 60) {
                // Left Content
                VStack(alignment: .leading, spacing: 30) {
                    // Branding Header
                    HStack(spacing: 8) {
                        Text(loc.text("系统优化", "System Optimization"))
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        // Optimization Icon
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text(loc.text("全面提速", "Full Boost"))
                                .font(.system(size: 20, weight: .heavy))
                        }
                        .foregroundColor(.white)
                    }
                    
                    Text(loc.text("通过控制 Mac 上运行的应用，提高它的输出。\n上次优化时间：从未", "Improve output by controlling apps running on your Mac.\nLast optimized: Never"))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .lineSpacing(4)
                    
                    // Feature Rows
                    VStack(alignment: .leading, spacing: 24) {
                        featureRow(
                            icon: "light.beacon.max.fill",
                            title: loc.text("管理启动代理", "Manage Launch Agents"),
                            desc: loc.text("控制您的 Mac 支持的应用。", "Control applications supported by your Mac.")
                        )
                        
                        featureRow(
                            icon: "waveform.path.ecg",
                            title: loc.text("控制运行的应用", "Control Running Apps"),
                            desc: loc.text("管理所有登录项，仅运行真正需要的项目。", "Manage login items, running only what you truly need.")
                        )
                        
                        featureRow(
                            icon: "chart.xyaxis.line",
                            title: loc.text("占用资源项目", "Heavy Consumers"),
                            desc: loc.text("找出并关闭占用太多资源的进程。", "Find and quit processes using too many resources.")
                        )
                    }
                    
                    // View Items Button
                    Button(action: { viewState = 1 }) {
                        Text(loc.text("查看项目...", "View Items..."))
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
                
                // Right Icon - Using youhua.png
                ZStack {
                    if let path = Bundle.main.path(forResource: "youhua", ofType: "png"),
                       let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 320, height: 320)
                            .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
                    } else {
                        // Fallback: Purple Circle with Sliders
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "C86FC9"), Color(hex: "8B3A9B")],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 280, height: 280)
                                .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
                            
                            // Sliders (Visual)
                            HStack(spacing: 30) {
                                // Slider 1
                                VStack(spacing: 0) {
                                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 60)
                                    Circle().fill(Color.white).frame(width: 24, height: 24)
                                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 100)
                                }
                                // Slider 2
                                VStack(spacing: 0) {
                                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 100)
                                    Circle().fill(Color.white).frame(width: 24, height: 24)
                                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 60)
                                }
                                // Slider 3
                                VStack(spacing: 0) {
                                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 40)
                                    Circle().fill(Color.white).frame(width: 24, height: 24)
                                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 120)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
            
            // Bottom Floating Button
            VStack {
                Spacer()
                Button(action: { viewState = 1 }) {
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
                        
                        Text(loc.text("开始", "Start"))
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
    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}


// MARK: - Memory Confirmation Dialog
struct MemoryConfirmationDialog: View {
    @ObservedObject var service: OptimizerService
    @ObservedObject var loc: LocalizationManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.text("内存优化", "Memory Optimization"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(loc.text("发现以下应用占用大量内存，是否需要关闭以释放内存？", "The following apps are using high memory. Close them to free up RAM?"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                
                Button(action: {
                    service.cancelMemoryApplications()
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            // App List
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($service.highMemoryApps) { $app in
                        HStack(spacing: 12) {
                            // Checkbox
                            Button(action: { app.isSelected.toggle() }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(app.isSelected ? Color.blue : Color.gray, lineWidth: 1.5)
                                        .frame(width: 18, height: 18)
                                    
                                    if app.isSelected {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.blue)
                                            .frame(width: 18, height: 18)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            
                            // App Icon
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 36, height: 36)
                            
                            // App Info
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                
                                Text(loc.text("内存占用: \(app.usageDescription)", "Memory: \(app.usageDescription)"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(app.isSelected ? Color.blue.opacity(0.05) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { app.isSelected.toggle() }
                        
                        if app.id != service.highMemoryApps.last?.id {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(service.highMemoryApps.count) * 60 + 20, 300))
            
            Divider()
            
            // Footer Actions
            HStack(spacing: 12) {
                // Select/Deselect All
                Button(action: {
                    let allSelected = service.highMemoryApps.allSatisfy { $0.isSelected }
                    for index in service.highMemoryApps.indices {
                        service.highMemoryApps[index].isSelected = !allSelected
                    }
                }) {
                    Text(service.highMemoryApps.allSatisfy { $0.isSelected } ? 
                         (loc.text("取消全选", "Deselect All")) : 
                         (loc.text(
    simplifiedChinese: "全选",
    traditionalChinese: "全選",
    english: "Select All",
    japanese: "すべてを選択",
    korean: "전체선택",
    russian: "Выбрать все"
)))
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Ignore Button
                Button(action: {
                    service.cancelMemoryApplications()
                    dismiss()
                }) {
                    Text(loc.text("忽略", "Ignore"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Close Apps Button
                Button(action: {
                    service.confirmMemoryApplications()
                    dismiss()
                }) {
                    Text(loc.text("关闭应用", "Close Apps"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(service.highMemoryApps.filter { $0.isSelected }.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Boot Optimization Dialog
struct BootOptimizationDialog: View {
    @ObservedObject var service: OptimizerService
    @ObservedObject var loc: LocalizationManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loc.text("启动加速", "Boot Optimization"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(loc.text("以下启动代理将被禁用以加快系统启动速度。请谨慎选择，禁用必要的启动项可能导致某些应用功能异常。", "The following launch agents will be disabled to speed up boot time. Choose carefully - disabling essential items may affect app functionality."))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                
                Button(action: {
                    service.bootAlertIgnored = true
                    service.showBootConfirmAlert = false
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            // Warning Banner
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 16))
                
                Text(loc.text("建议仅禁用您确认不需要的启动项", "Only disable launch agents you're sure you don't need"))
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.1))
            
            // Agent List
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($service.bootAgentsToDisable) { $agent in
                        HStack(spacing: 12) {
                            // Checkbox
                            Button(action: { agent.isSelected.toggle() }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(agent.isSelected ? Color.blue : Color.gray, lineWidth: 1.5)
                                        .frame(width: 18, height: 18)
                                    
                                    if agent.isSelected {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Color.blue)
                                            .frame(width: 18, height: 18)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            
                            // Icon
                            Image(nsImage: agent.icon)
                                .resizable()
                                .frame(width: 36, height: 36)
                            
                            // Agent Info
                            VStack(alignment: .leading, spacing: 2) {
                                Text(agent.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Text(agent.label)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            // Status Badge
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(agent.isEnabled ? Color.green : Color.gray)
                                    .frame(width: 6, height: 6)
                                Text(agent.isEnabled ? 
                                     (loc.text("已启用", "Enabled")) : 
                                     (loc.text("已禁用", "Disabled")))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(agent.isSelected ? Color.blue.opacity(0.05) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { agent.isSelected.toggle() }
                        
                        if agent.id != service.bootAgentsToDisable.last?.id {
                            Divider()
                                .padding(.leading, 72)
                        }
                    }
                }
            }
            .frame(height: min(CGFloat(service.bootAgentsToDisable.count) * 60 + 20, 350))
            
            Divider()
            
            // Footer Actions
            HStack(spacing: 12) {
                // Select/Deselect All
                Button(action: {
                    let allSelected = service.bootAgentsToDisable.allSatisfy { $0.isSelected }
                    for index in service.bootAgentsToDisable.indices {
                        service.bootAgentsToDisable[index].isSelected = !allSelected
                    }
                }) {
                    Text(service.bootAgentsToDisable.allSatisfy { $0.isSelected } ? 
                         (loc.text("取消全选", "Deselect All")) : 
                         (loc.text(
    simplifiedChinese: "全选",
    traditionalChinese: "全選",
    english: "Select All",
    japanese: "すべてを選択",
    korean: "전체선택",
    russian: "Выбрать все"
)))
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Skip Button
                Button(action: {
                    service.bootAlertIgnored = true
                    service.showBootConfirmAlert = false
                    dismiss()
                }) {
                    Text(loc.text("跳过", "Skip"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Disable Button
                Button(action: {
                    Task {
                        await service.disableSelectedBootAgents()
                        dismiss()
                    }
                }) {
                    Text(loc.text("禁用选中项", "Disable Selected"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(service.bootAgentsToDisable.filter { $0.isSelected }.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 550)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
