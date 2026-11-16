import Foundation
import AppKit
import UserNotifications

protocol DownloadsWatchHandle: AnyObject { func cancel() }

private final class DirectoryDownloadsWatch: DownloadsWatchHandle {
    private let source: DispatchSourceFileSystemObject

    init(url: URL, changed: @escaping () -> Void) throws {
        let descriptor = open(url.path, O_EVTONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
                                                           queue: DispatchQueue(label: "com.macoptimizer.download-watch", qos: .utility))
        source.setEventHandler(handler: changed)
        // Capture this watcher's descriptor, never a mutable descriptor from the service.
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }
    func cancel() { source.cancel() }
    deinit { source.cancel() }
}

@MainActor
final class ProtectionService: ObservableObject {
    static let shared = ProtectionService()
    static let monitoringPreferenceKey = "Protection.DownloadNameMonitoringEnabled"

    @Published private(set) var isMonitoring = false
    @Published private(set) var monitoringError: String?
    @Published private(set) var threatHistory: [DetectedThreat] = []
    // No browser content blocker is connected. Never restore simulated counters.
    @Published private(set) var adBlockedCount = 0
    @Published private(set) var blockedAds: [BlockedAd] = []
    @Published private(set) var contentBlockerConnected = false

    struct BlockedAd: Identifiable {
        let id = UUID()
        let domain: String
        let date: Date
        let source: String
    }

    private let downloadsDirectory: URL
    private let defaults: UserDefaults
    private let watchFactory: (URL, @escaping () -> Void) throws -> DownloadsWatchHandle
    private let scanFile: (URL) -> DetectedThreat?
    private let notify: (DetectedThreat) -> Void
    private var watch: DownloadsWatchHandle?
    private var checkTask: Task<Void, Never>?
    private var sessionID: UUID?
    private var reportedVersions: [String: Date] = [:]

    init(downloadsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"),
         defaults: UserDefaults = .standard,
         watchFactory: @escaping (URL, @escaping () -> Void) throws -> DownloadsWatchHandle = { try DirectoryDownloadsWatch(url: $0, changed: $1) },
         scanFile: ((URL) -> DetectedThreat?)? = nil,
         notify: ((DetectedThreat) -> Void)? = nil,
         resumeSavedPreference: Bool = true) {
        self.downloadsDirectory = downloadsDirectory
        self.defaults = defaults
        self.watchFactory = watchFactory
        let scanner = MalwareScanner()
        self.scanFile = scanFile ?? { scanner.scanFile(at: $0) }
        self.notify = notify ?? Self.sendNotification
        if resumeSavedPreference && defaults.bool(forKey: Self.monitoringPreferenceKey) {
            startMonitoring()
        }
    }

    deinit { checkTask?.cancel(); watch?.cancel() }

    func startMonitoring() {
        guard watch == nil else { return }
        let id = UUID()
        sessionID = id
        monitoringError = nil
        do {
            watch = try watchFactory(downloadsDirectory) { [weak self] in
                Task { @MainActor in
                    guard let self, self.sessionID == id, self.isMonitoring else { return }
                    self.scheduleCheck(session: id)
                }
            }
            isMonitoring = true
            defaults.set(true, forKey: Self.monitoringPreferenceKey)
            // Watch future changes; enabling this option does not scan existing downloads.
        } catch {
            sessionID = nil
            isMonitoring = false
            monitoringError = error.localizedDescription
            defaults.set(false, forKey: Self.monitoringPreferenceKey)
        }
    }

    func stopMonitoring() {
        sessionID = nil
        isMonitoring = false
        checkTask?.cancel()
        checkTask = nil
        watch?.cancel()
        watch = nil
        defaults.set(false, forKey: Self.monitoringPreferenceKey)
    }

    private func scheduleCheck(session: UUID) {
        // Coalesce bursts while a browser writes/renames a download.
        checkTask?.cancel()
        let folder = downloadsDirectory
        let scan = scanFile
        checkTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            let worker = Task.detached(priority: .utility) { () -> [(DetectedThreat, Date)] in
                guard let urls = try? FileManager.default.contentsOfDirectory(at: folder,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
                var findings: [(DetectedThreat, Date)] = []
                for url in urls {
                    if Task.isCancelled { break }
                    guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey]),
                          values.isSymbolicLink != true, let modified = values.contentModificationDate,
                          Date().timeIntervalSince(modified) < 60, let threat = scan(url) else { continue }
                    findings.append((threat, modified))
                }
                return findings
            }
            let findings = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.sessionID == session, self.isMonitoring else { return }
            for (threat, modified) in findings {
                let key = threat.path.path
                guard self.reportedVersions[key] != modified else { continue }
                self.reportedVersions[key] = modified
                if !self.threatHistory.contains(where: { $0.path == threat.path }) {
                    self.threatHistory.append(threat)
                    self.notify(threat)
                }
            }
            self.checkTask = nil
        }
    }

    private static func sendNotification(_ threat: DetectedThreat) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "下载项目需要检查 / Review a downloaded item"
            content.body = "\(threat.path.lastPathComponent): \(threat.evidenceSummary)"
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: threat.id.uuidString, content: content, trigger: nil))
        }
    }
}
