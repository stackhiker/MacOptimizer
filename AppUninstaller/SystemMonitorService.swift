import Foundation
import Combine
import AppKit
import CoreWLAN
import IOKit

struct HighMemoryApp: Identifiable {
    let id: pid_t
    let name: String
    let usage: Double // GB
    let icon: NSImage?
}

class SystemMonitorService: ObservableObject {
    static let shared = SystemMonitorService()
    private let metrics = SystemMetricsSampler()
    enum MonitoringScope { case all, overview, network }
    private var monitoringClients: [String: MonitoringScope] = [:]
    private let diskSampler = DiskIOSampler()
    @Published private(set) var cpuUsageHistory: [Double] = []
    @Published private(set) var diskReadSpeed: Double?
    @Published private(set) var diskWriteSpeed: Double?
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0 // Percentage
    @Published var memoryUsedString: String = "0 GB"
    @Published var memoryTotalString: String = "0 GB"
    
    // High Memory Alert
    @Published var highMemoryApp: HighMemoryApp?
    @Published var showHighMemoryAlert: Bool = false
    // Threshold set to 2GB as requested
    private let memoryThresholdGB: Double = 2.0 
    private var ignoredPids: Set<pid_t> = []
    
    // 新增：定时提醒和永久忽略
    private var snoozedUntil: Date?  // 暂停提醒直到此时间
    private var permanentlyIgnoredApps: Set<String> = []  // 永久忽略的应用名称列表
    private let ignoredAppsKey = "MemoryMonitor.IgnoredApps"
    
    // Network Speed Monitoring
    @Published var downloadSpeed: Double = 0.0 // bytes per second
    @Published var uploadSpeed: Double = 0.0   // bytes per second
    @Published var downloadSpeedHistory: [Double] = Array(repeating: 0, count: 20)
    @Published var uploadSpeedHistory: [Double] = Array(repeating: 0, count: 20)
    
    
    // Battery Monitoring
    @Published var batteryLevel: Double = 0.0
    @Published private(set) var batteryDataAvailable = false
    @Published private(set) var isPowerConnected = false
    @Published var isCharging: Bool = false
    @Published var batteryState: String = "—"
    @Published var batteryTimeRemaining: String = ""
    
    private var timer: Timer?
    private let monitorQueue = DispatchQueue(
        label: "com.macoptimizer.system-monitor",
        qos: .utility
    )
    private var isUpdateInFlight = false
    private var updateCycle = 0
    
    // UI Update Batching
    private let uiUpdater = BatchedUIUpdater(debounceDelay: 0.05)

    // Process Monitoring
    struct AppProcess: Identifiable {
        let id: pid_t
        let name: String
        let icon: NSImage?
        let cpu: Double // Percentage
        let memory: Double // GB
    }
    
    @Published var topMemoryProcesses: [AppProcess] = []
    @Published var topCPUProcesses: [AppProcess] = []
    
    // Speed Test
    @Published var isTestingSpeed: Bool = false
    @Published var speedTestResult: Double = 0.0 // Mbps
    @Published var speedTestProgress: Double = 0.0
    
    // WiFi Info
    @Published var wifiSSID: String = "Wi-Fi"
    @Published var wifiSecurity: String = "—"
    @Published var wifiSignalStrength: String = "—"
    @Published var connectionDuration: String = "—"
    private var connectionStartTime: Date = Date()
    
    // Total Traffic
    @Published var totalDownload: String = "0 KB"
    @Published var totalUpload: String = "0 KB"
    
    // ... updateStats logic ...
    
    private func fetchUserProcesses() {
        // 1. Get User Apps from NSWorkspace (GUI Apps)
        let runningApps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        
        // 2. Scan ALL user processes to build a process tree
        // ps -x -o pid,ppid,%cpu,rss,comm
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "ps -x -o pid,ppid,%cpu,rss,comm | tail -n +2"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse all processes
                struct ProcessInfo {
                    let pid: Int32
                    let ppid: Int32
                    let cpu: Double
                    let rss: Double // GB
                    let name: String
                }
                
                var allProcesses: [Int32: ProcessInfo] = [:]
                var childrenMap: [Int32: [Int32]] = [:] // Parent -> [Children]
                
                let lines = output.components(separatedBy: "\n")
                for line in lines {
                    let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 5,
                       let pid = Int32(parts[0]),
                       let ppid = Int32(parts[1]),
                       let cpu = Double(parts[2]),
                       let rssKB = Double(parts[3]) {
                        
                        // Extract name (rest of the line)
                        let nameParts = parts.dropFirst(4)
                        let fullPath = nameParts.joined(separator: " ")
                        let name = URL(fileURLWithPath: fullPath).lastPathComponent
                        
                        let info = ProcessInfo(pid: pid, ppid: ppid, cpu: cpu, rss: rssKB / 1024.0 / 1024.0, name: name)
                        allProcesses[pid] = info
                        
                        // Build tree
                        childrenMap[ppid, default: []].append(pid)
                    }
                }
                
                // Helper to calculate total stats recursively
                func getAggregatedStats(for pid: Int32, visited: inout Set<Int32>) -> (cpu: Double, mem: Double) {
                    if visited.contains(pid) { return (0, 0) }
                    visited.insert(pid)
                    
                    var totalCPU = 0.0
                    var totalMem = 0.0
                    
                    if let process = allProcesses[pid] {
                        totalCPU += process.cpu
                        totalMem += process.rss
                    }
                    
                    if let children = childrenMap[pid] {
                        for child in children {
                            let childStats = getAggregatedStats(for: child, visited: &visited)
                            totalCPU += childStats.cpu
                            totalMem += childStats.mem
                        }
                    }
                    
                    return (totalCPU, totalMem)
                }
                
                // 3. Aggregate stats for each App
                var appProcesses: [AppProcess] = []

                
                for app in runningApps {
                    let pid = app.processIdentifier
                    // Only process if valid and not already counted (though unlikely for main apps to duplicate)
                    
                    var visited = Set<Int32>() // Visited for this app's tree
                    let stats = getAggregatedStats(for: pid, visited: &visited)
                    
                    // Add app stats
                    appProcesses.append(AppProcess(
                        id: pid,
                        name: app.localizedName ?? "Unknown",
                        icon: app.icon,
                        cpu: stats.cpu,
                        memory: stats.mem
                    ))
                    
                    // Mark these PIDs as processed if we want to avoid double counting if we were scanning all processes.
                    // But here we only care about the Apps list from NSWorkspace.
                }
                
                // Sort and Update
                let sortedByMem = appProcesses.sorted { $0.memory > $1.memory }.prefix(10)
                let sortedByCPU = appProcesses.sorted { $0.cpu > $1.cpu }.prefix(10)
                
                DispatchQueue.main.async {
                    self.topMemoryProcesses = Array(sortedByMem)
                    self.topCPUProcesses = Array(sortedByCPU)
                }
            }
        } catch {
            print("User Process Scan Error: \(error)")
        }
    }
    
    func runSpeedTest() {
        guard !isTestingSpeed else { return }
        isTestingSpeed = true
        speedTestResult = 0
        speedTestProgress = 0
        
        // Simple download test (download a 10MB file or similar)
        // Using a reliable CDN test file (e.g., Cloudflare)
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=10000000") else { return }
        
        let startTime = Date()
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isTestingSpeed = false
                self?.speedTestProgress = 1.0
                
                if let data = data {
                    let duration = Date().timeIntervalSince(startTime)
                    let bits = Double(data.count) * 8
                    let mbps = (bits / duration) / 1_000_000
                    self?.speedTestResult = mbps
                }
            }
        }
        
        // Fake Progress or delegate? simpler for now just wait.
        // Or implement delegate for progress.
        task.resume()
    }
    
    // ... add fetchUserProcesses() to updateStats ...
    
    init() {
        // Disable high memory alert for the first 30 seconds after app launch
        snoozedUntil = Date().addingTimeInterval(30)
        
        loadIgnoredApps()
    }

    deinit {
        timer?.invalidate()
    }
    
    /// 从UserDefaults加载永久忽略的应用列表
    private func loadIgnoredApps() {
        if let savedApps = UserDefaults.standard.array(forKey: ignoredAppsKey) as? [String] {
            permanentlyIgnoredApps = Set(savedApps)
        }
    }
    
    /// 保存永久忽略的应用列表到UserDefaults
    private func saveIgnoredApps() {
        UserDefaults.standard.set(Array(permanentlyIgnoredApps), forKey: ignoredAppsKey)
    }
    
    func startMonitoring(client: String = "default", scope: MonitoringScope = .all) {
        let changedScope = monitoringClients[client] != scope
        monitoringClients[client] = scope
        guard timer == nil else {
            if changedScope { updateCycle = 0; scheduleUpdate() }
            return
        }

        updateCycle = 0
        scheduleUpdate()

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.scheduleUpdate()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    
    func stopMonitoring(client: String = "default") {
        monitoringClients[client] = nil
        guard monitoringClients.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }

    private func scheduleUpdate() {
        guard !isUpdateInFlight else { return }

        isUpdateInFlight = true
        let cycle = updateCycle
        updateCycle += 1

        let scopes = Array(monitoringClients.values)
        monitorQueue.async { [weak self] in
            guard let self else { return }
            self.updateStats(cycle: cycle, scopes: scopes)

            DispatchQueue.main.async { [weak self] in
                self?.isUpdateInFlight = false
            }
        }
    }
    
    // 格式化网络速度
    func formatSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: "%.1f GB/s", bytesPerSecond / 1_000_000_000)
        } else if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }
    
    private func updateStats(cycle: Int, scopes: [MonitoringScope]) {
        let needsOverview = scopes.contains(.all) || scopes.contains(.overview)
        let needsBattery = scopes.contains(.all)
        let shouldRefreshApplications = needsOverview && cycle.isMultiple(of: 5)
        let shouldRefreshBatteryDetails = needsBattery && cycle.isMultiple(of: 30)

        if shouldRefreshApplications {
            checkHighMemoryApps()
            fetchUserProcesses()
        }
        
        if needsOverview, let usage = metrics.cpuUsage() {
            DispatchQueue.main.async {
                self.cpuUsage = usage
                self.cpuUsageHistory = Array((self.cpuUsageHistory + [usage]).suffix(40))
            }
        }

        if needsOverview, let snapshot = MemorySnapshot.read() {
            DispatchQueue.main.async {
                self.memoryUsage = snapshot.usage
                self.memoryUsedString = ByteCountFormatter.string(fromByteCount: Int64(snapshot.usedBytes), countStyle: .memory)
                self.memoryTotalString = ByteCountFormatter.string(fromByteCount: Int64(snapshot.totalBytes), countStyle: .memory)
                let total = Double(max(1, snapshot.totalBytes))
                self.memoryApp = Double(snapshot.appBytes) / total
                self.memoryWired = Double(snapshot.wiredBytes) / total
                self.memoryCompressed = Double(snapshot.compressedBytes) / total
                self.memoryPressureLevel = snapshot.pressure
                self.memorySwapUsed = snapshot.swapUsedBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) } ?? "—"
                self.systemUptime = ProcessInfo.processInfo.systemUptime
            }
        }

        if needsOverview {
            let rates = diskSampler.read()
            DispatchQueue.main.async { self.diskReadSpeed = rates?.read; self.diskWriteSpeed = rates?.written }
        }
        if shouldRefreshBatteryDetails {
            updateBatteryDetails()
        }
        
        if let traffic = metrics.networkUsage() {
            DispatchQueue.main.async {
                self.downloadSpeed = traffic.download
                self.uploadSpeed = traffic.upload
                self.totalDownload = ByteCountFormatter.string(fromByteCount: Int64(clamping: traffic.received), countStyle: .file)
                self.totalUpload = ByteCountFormatter.string(fromByteCount: Int64(clamping: traffic.sent), countStyle: .file)
                self.downloadSpeedHistory = Array((self.downloadSpeedHistory + [traffic.download]).suffix(20))
                self.uploadSpeedHistory = Array((self.uploadSpeedHistory + [traffic.upload]).suffix(20))
            }
        }

        if cycle.isMultiple(of: 5) {
            fetchWiFiInfo()
            if needsBattery { updateBatteryStatus() }
        }
        updateConnectionDuration()
    }
    
    private func fetchWiFiInfo() {
        let ssid = CWWiFiClient.shared().interface()?.ssid()
        DispatchQueue.main.async {
            self.wifiSSID = ssid ?? LocalizationManager.shared.text("无法获取 Wi-Fi 信息", "Wi-Fi Information Unavailable")
        }
    }

    private func updateConnectionDuration() {
        let duration = Date().timeIntervalSince(connectionStartTime)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        Task {
            await uiUpdater.batch {
                self.connectionDuration = LocalizationManager.shared.text(
                    simplifiedChinese: "\(hours)小时 \(minutes)分钟 \(seconds)秒",
                    traditionalChinese: "\(hours)小時 \(minutes)分鐘 \(seconds)秒",
                    english: "\(hours) hr \(minutes) min \(seconds) sec",
                    japanese: "\(hours)時間 \(minutes)分 \(seconds)秒",
                    korean: "\(hours)시간 \(minutes)분 \(seconds)초",
                    russian: "\(hours) ч \(minutes) мин \(seconds) с"
                )
            }
        }
    }
    
    private func readBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        return properties?.takeRetainedValue() as? [String: Any]
    }

    private func updateBatteryStatus() {
        let properties = readBatteryProperties()
        let maxCapacity = (properties?["MaxCapacity"] as? NSNumber)?.doubleValue
        let current = (properties?["CurrentCapacity"] as? NSNumber)?.doubleValue
        let connected = (properties?["ExternalConnected"] as? NSNumber)?.boolValue ?? false
        let charging = (properties?["IsCharging"] as? NSNumber)?.boolValue ?? false
        DispatchQueue.main.async {
            guard let maxCapacity, let current, maxCapacity > 0 else {
                self.batteryDataAvailable = false
                self.batteryLevel = 0
                self.isCharging = false
                self.isPowerConnected = false
                self.batteryState = "—"
                self.batteryTimeRemaining = ""
                return
            }
            self.batteryDataAvailable = true
            self.batteryLevel = min(1, max(0, current / maxCapacity))
            self.isCharging = charging
            self.isPowerConnected = connected
            let loc = LocalizationManager.shared
            self.batteryState = connected ? (charging ? loc.text("正在充电", "Charging") : loc.text("已连接电源", "Power Connected")) : loc.text("使用电池", "On Battery")
            self.batteryTimeRemaining = ""
        }
    }

    func checkHighMemoryApps() {
        // 检查是否在暂停期间
        if let snoozedUntil = snoozedUntil, Date() < snoozedUntil {
            return  // 暂停期间不检测
        }
        
        guard MemorySnapshot.readPressure().isElevated else {
            DispatchQueue.main.async {
                self.highMemoryApp = nil
                self.showHighMemoryAlert = false
            }
            return
        }
        // Use ps to get pid and rss
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "ps -aceo pid,rss,comm"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: "\n")
                // Skip header (PID RSS COMM)
                
                var maxRSS: Double = 0
                var maxPID: pid_t = 0
                var maxName: String = ""
                
                for line in lines.dropFirst() {
                    let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if parts.count >= 3 {
                        if let pid = pid_t(parts[0]),
                           let rssKB = Double(parts[1]) {
                            
                            guard let runningApp = NSRunningApplication(processIdentifier: pid),
                                  runningApp.activationPolicy == .regular,
                                  runningApp.bundleIdentifier != "com.apple.finder" else { continue }
                            // Check ignore list and self
                            if pid == ProcessInfo.processInfo.processIdentifier { continue }
                            if ignoredPids.contains(pid) { continue }
                            
                            // 获取应用名称用于检查永久忽略列表
                            let tempName = parts[2...].joined(separator: " ")
                            var appName = tempName
                            if let app = NSRunningApplication(processIdentifier: pid) {
                                appName = app.localizedName ?? tempName
                            }
                            
                            // 检查是否在永久忽略列表中
                            if permanentlyIgnoredApps.contains(appName) {
                                continue
                            }
                                                        
                            let rssGB = rssKB / 1024.0 / 1024.0
                            
                            if rssGB > memoryThresholdGB && rssGB > maxRSS {
                                maxRSS = rssGB
                                maxPID = pid
                                maxName = appName
                            }
                        }
                    }
                }
                
                let alert: HighMemoryApp? = maxRSS > 0
                    ? HighMemoryApp(id: maxPID, name: maxName, usage: maxRSS,
                                    icon: NSRunningApplication(processIdentifier: maxPID)?.icon)
                    : nil
                DispatchQueue.main.async {
                    self.highMemoryApp = alert
                    self.showHighMemoryAlert = alert != nil
                }
            }
        } catch {
            print("Process Scan Error: \(error)")
        }
    }
    
    func ignoreCurrentHighMemoryApp() {
        if let app = highMemoryApp {
            ignoredPids.insert(app.id)
            
            Task {
                await uiUpdater.batch {
                    self.highMemoryApp = nil
                    self.showHighMemoryAlert = false
                }
            }
        }
    }
    
    /// 暂停内存警告一段时间（定时提醒）
    /// - Parameter minutes: 暂停的分钟数
    func snoozeAlert(minutes: Int) {
        snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        
        // 暂时关闭当前警告
        Task {
            await uiUpdater.batch {
                self.highMemoryApp = nil
                self.showHighMemoryAlert = false
            }
        }
        
        print("[MemoryMonitor] Snoozed for \(minutes) minutes until \(snoozedUntil!)")
    }
    
    /// 永久忽略当前高内存应用
    func ignoreAppPermanently() {
        guard let app = highMemoryApp else { return }
        
        // 添加到永久忽略列表
        permanentlyIgnoredApps.insert(app.name)
        saveIgnoredApps()
        
        // 关闭警告
        Task {
            await uiUpdater.batch {
                self.highMemoryApp = nil
                self.showHighMemoryAlert = false
            }
        }
        
        print("[MemoryMonitor] Permanently ignored app: \(app.name)")
    }
    
    /// 移除永久忽略的应用（用于设置界面）
    /// - Parameter appName: 应用名称
    func removeFromIgnoredApps(_ appName: String) {
        permanentlyIgnoredApps.remove(appName)
        saveIgnoredApps()
    }
    
    /// 获取所有永久忽略的应用列表
    func getIgnoredApps() -> [String] {
        return Array(permanentlyIgnoredApps).sorted()
    }
    
    /// 清除所有永久忽略的应用
    func clearAllIgnoredApps() {
        permanentlyIgnoredApps.removeAll()
        saveIgnoredApps()
    }
    
    @MainActor
    func terminateHighMemoryApp() {
        guard let item = highMemoryApp,
              let app = NSRunningApplication(processIdentifier: item.id),
              app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.localizedName == item.name else { return }
        // A normal quit request lets the application present a save dialog.
        // Dismiss this suggestion only if the request was accepted.
        if app.terminate() {
            highMemoryApp = nil
            showHighMemoryAlert = false
            snoozedUntil = Date().addingTimeInterval(60)
        }
    }

    @Published var systemUptime: TimeInterval = 0
    @Published var memoryApp: Double = 0
    @Published var memoryWired: Double = 0
    @Published var memoryCompressed: Double = 0
    @Published var memoryPressureLevel: MemoryPressureLevel = .unknown
    @Published var memorySwapUsed: String = "0 B"
    @Published var memorySwapTotal: String = "0 B"
    @Published var batteryHealth: String = "—"
    @Published var batteryCycleCount: Int = -1
    @Published var batteryCondition: String = "—"
    
    private func updateBatteryDetails() {
        let properties = readBatteryProperties() ?? [:]
        let cycle = (properties["CycleCount"] as? NSNumber)?.intValue
        let design = (properties["DesignCapacity"] as? NSNumber)?.doubleValue
        let maximum = (properties["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
        let health = properties["BatteryHealth"] as? String
        DispatchQueue.main.async {
            self.batteryCycleCount = cycle ?? -1
            if let design, let maximum, design > 0 {
                self.batteryHealth = String(format: "%.0f%%", min(100, max(0, maximum / design * 100)))
            } else { self.batteryHealth = "—" }
            self.batteryCondition = health ?? "—"
        }
    }

}
