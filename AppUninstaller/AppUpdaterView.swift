import SwiftUI
import AppKit

struct AppUpdateItem: Identifiable {
    let id: String
    let app: InstalledApp
    let newVersion: String
}

struct AppUpdateRecord: Identifiable {
    let application: UpdateApplication
    let check: UpdateCheck
    let icon: NSImage
    let automaticUpdateUnavailableReason: String?
    var id: String { application.path.path }
}

/// FIFO permit pool for bounded parallel update preparation. Cancellation of a
/// waiting task removes only that task and never consumes a permit.
actor AppUpdateConcurrencyGate {
    private struct Waiter {
        let id: String
        let continuation: CheckedContinuation<Void, Error>
    }

    let limit: Int
    private var activeIDs = Set<String>()
    private var waiters: [Waiter] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire(_ id: String) async throws {
        try Task.checkCancellation()
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    if activeIDs.count < limit {
                        activeIDs.insert(id)
                        continuation.resume()
                    } else {
                        waiters.append(Waiter(id: id, continuation: continuation))
                    }
                }
            } onCancel: {
                Task { await self.cancelWaiter(id) }
            }
            try Task.checkCancellation()
        } catch {
            if activeIDs.remove(id) != nil { resumeWaitersIfPossible() }
            throw error
        }
    }

    func release(_ id: String) {
        guard activeIDs.remove(id) != nil else { return }
        resumeWaitersIfPossible()
    }

    func snapshot() -> (active: Set<String>, queued: [String]) {
        (activeIDs, waiters.map(\.id))
    }

    private func cancelWaiter(_ id: String) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func resumeWaitersIfPossible() {
        while activeIDs.count < limit, !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            activeIDs.insert(waiter.id)
            waiter.continuation.resume()
        }
    }
}

@MainActor
final class AppUpdaterService: ObservableObject {
    static let shared = AppUpdaterService()
    @Published private(set) var updates: [AppUpdateItem] = []
    @Published private(set) var records: [AppUpdateRecord] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanComplete = false
    @Published private(set) var progress = 0.0
    @Published private(set) var scannedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var lastChecked: Date?
    @Published private(set) var queuedUpdateIDs: [String] = []
    @Published private(set) var activeUpdateIDs = Set<String>()
    @Published private(set) var installationStates: [String: AppUpdateInstallStatus] = [:]
    private let installer: AppUpdateInstaller
    private let updateGate: AppUpdateConcurrencyGate
    private let installQueue = BackgroundTaskQueue()
    private var updateTasks: [String: Task<Void, Never>] = [:]

    init(installer: AppUpdateInstaller = AppUpdateInstaller(), initialRecords: [AppUpdateRecord] = [], maxConcurrentUpdates: Int = 3) {
        self.installer = installer
        updateGate = AppUpdateConcurrencyGate(limit: maxConcurrentUpdates)
        records = initialRecords
        scanComplete = !initialRecords.isEmpty
    }

    var hasScheduledUpdates: Bool { !queuedUpdateIDs.isEmpty || !activeUpdateIDs.isEmpty }

    func isUpdateScheduled(_ id: String) -> Bool {
        queuedUpdateIDs.contains(id) || activeUpdateIDs.contains(id)
    }

    func queuedPosition(_ id: String) -> Int? {
        queuedUpdateIDs.firstIndex(of: id).map { $0 + 1 }
    }

    func scanForUpdates() async {
        guard !isScanning, !hasScheduledUpdates else { return }
        isScanning = true
        scanComplete = false
        records = []
        updates = []
        scannedCount = 0
        totalCount = 0
        progress = 0
        installationStates = [:]
        defer { isScanning = false }

        // Update checks only need bundle metadata, not recursive application sizes.
        let applications = await Task.detached(priority: .userInitiated) { UpdateApplication.installed() }.value
        totalCount = applications.count
        let lookup = AppUpdateLookup()
        await withTaskGroup(of: (UpdateApplication, UpdateCheck).self) { group in
            var iterator = applications.makeIterator()
            for _ in 0..<6 {
                if let app = iterator.next() { group.addTask { (app, await lookup.check(app)) } }
            }
            while let (app, check) = await group.next() {
                let icon = NSWorkspace.shared.icon(forFile: app.path.path)
                let reason = check.state == .available ? AppUpdateInstaller.unavailableReason(for: app, check: check) : nil
                records.append(AppUpdateRecord(application: app, check: check, icon: icon, automaticUpdateUnavailableReason: reason))
                records.sort { $0.application.name.localizedStandardCompare($1.application.name) == .orderedAscending }
                if check.state == .available {
                    let installed = InstalledApp(name: app.name, path: app.path, bundleIdentifier: app.bundleID,
                                                 icon: icon, size: 0, isAppStore: app.isAppStore, version: app.version)
                    updates.append(AppUpdateItem(id: app.path.path, app: installed, newVersion: check.version))
                }
                scannedCount += 1
                progress = Double(scannedCount) / Double(max(1, totalCount))
                if let app = iterator.next() { group.addTask { (app, await lookup.check(app)) } }
            }
        }
        progress = 1
        lastChecked = Date()
        scanComplete = true
    }

    func update(_ record: AppUpdateRecord) {
        guard !isScanning, let asset = record.check.asset,
              record.automaticUpdateUnavailableReason == nil,
              !isUpdateScheduled(record.id) else { return }
        let id = record.id
        queuedUpdateIDs.append(id)
        installationStates[id] = .init(phase: .queued)
        let task = Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            var acquired = false
            do {
                try await self.updateGate.acquire(id)
                acquired = true
                self.queuedUpdateIDs.removeAll { $0 == id }
                self.activeUpdateIDs.insert(id)
                try await self.performUpdate(record, asset: asset)
            } catch is CancellationError {
                self.installationStates[id] = .init(phase: .cancelled)
            } catch {
                self.installationStates[id] = .init(phase: .failed, message: error.localizedDescription)
            }
            if acquired { await self.updateGate.release(id) }
            self.queuedUpdateIDs.removeAll { $0 == id }
            self.activeUpdateIDs.remove(id)
            self.updateTasks.removeValue(forKey: id)
        }
        updateTasks[id] = task
    }

    func cancelUpdate(_ id: String) {
        guard installationStates[id]?.phase.canCancel == true else { return }
        updateTasks[id]?.cancel()
    }

    private func performUpdate(_ record: AppUpdateRecord, asset: AppUpdateAsset) async throws {
        let id = record.id
        var prepared: PreparedAppUpdate?
        do {
            let update = try await installer.prepare(application: record.application, asset: asset) { status in
                Task { @MainActor in
                    guard self.activeUpdateIDs.contains(id), self.updateTasks[id]?.isCancelled != true else { return }
                    self.installationStates[id] = status
                }
            }
            prepared = update
            try Task.checkCancellation()
            installationStates[id] = .init(phase: .waitingToInstall)
            let result = try await installQueue.enqueue { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.installPrepared(update, record: record)
            }
            prepared = nil
            installationStates[id] = .init(phase: .completed, backup: result.backup)
            if let installed = UpdateApplication.read(at: record.application.path),
               let index = records.firstIndex(where: { $0.id == id }) {
                let check = UpdateCheck(state: .current, source: record.check.source, version: installed.version, url: record.check.url)
                records[index] = AppUpdateRecord(application: installed, check: check, icon: record.icon, automaticUpdateUnavailableReason: nil)
            }
            updates.removeAll { $0.id == id }
            if result.reopen {
                reopen(record.application, id: id)
            }
        } catch {
            if let prepared { await installer.discard(prepared) }
            throw error
        }
    }

    private func installPrepared(_ update: PreparedAppUpdate, record: AppUpdateRecord) async throws -> (backup: URL, reopen: Bool) {
        let id = record.id
        try Task.checkCancellation()
        let running = runningApplications(for: record.application)
        let reopen = !running.isEmpty
        if reopen {
            installationStates[id] = .init(phase: .quitting)
            for application in running where !application.isTerminated {
                guard application.terminate() else {
                    throw AppUpdateInstallError.rejected("应用未同意退出，请保存工作并退出应用后重试")
                }
            }
            let deadline = Date().addingTimeInterval(20)
            while !runningApplications(for: record.application).isEmpty {
                try Task.checkCancellation()
                guard Date() < deadline else {
                    throw AppUpdateInstallError.rejected("应用仍在运行，请保存工作并退出应用后重试")
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        try Task.checkCancellation()
        let backup = try await installer.install(update) { status in
            Task { @MainActor in
                if self.activeUpdateIDs.contains(id), self.updateTasks[id]?.isCancelled != true {
                    self.installationStates[id] = status
                }
            }
        }
        return (backup, reopen)
    }

    private func reopen(_ application: UpdateApplication, id: String) {
        NSWorkspace.shared.openApplication(at: application.path, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                Task { @MainActor in
                    self.installationStates[id]?.message = "更新已完成，但无法自动打开应用：\(error.localizedDescription)"
                }
            }
        }
    }

    private func runningApplications(for application: UpdateApplication) -> [NSRunningApplication] {
        let path = application.path.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.filter {
            guard let bundle = $0.bundleURL?.resolvingSymlinksInPath().path else { return false }
            return bundle == path || bundle.hasPrefix(path + "/")
        }
    }
}

struct AppUpdaterView: View {
    @StateObject private var service: AppUpdaterService
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var filter: UpdateCheckState? = .available
    @State private var query = ""
    @State private var openError: String?
    @State private var pendingUpdate: AppUpdateRecord?

    @MainActor
    init(service: AppUpdaterService? = nil) {
        _service = StateObject(wrappedValue: service ?? .shared)
    }

    private func text(_ chinese: String, _ english: String) -> String { loc.text(chinese, english) }

    private func title(_ state: UpdateCheckState) -> String {
        switch state {
        case .available: return text("可更新", "Updates")
        case .current: return text("无更新", "No Update")
        case .unsupported: return text("暂不支持", "Unsupported")
        case .failed: return text("检测失败", "Failed")
        }
    }

    private func color(_ state: UpdateCheckState) -> Color {
        switch state {
        case .available: return .cyan
        case .current: return .green
        case .unsupported: return .secondary
        case .failed: return .orange
        }
    }

    private func count(_ state: UpdateCheckState) -> Int { service.records.filter { $0.check.state == state }.count }

    private var visibleRecords: [AppUpdateRecord] {
        service.records.filter { record in
            (filter == nil || record.check.state == filter ||
             (filter == .available && service.installationStates[record.id]?.phase == .completed)) &&
            (query.isEmpty || record.application.name.localizedCaseInsensitiveContains(query) ||
             record.application.bundleID.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.title2).foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("更新程序", "Updater")).font(.system(size: 22, weight: .semibold))
                    if service.isScanning {
                        Text(text("正在检查 \(service.scannedCount)/\(service.totalCount)", "Checking \(service.scannedCount)/\(service.totalCount)"))
                            .font(.caption).foregroundColor(.secondary)
                    } else if service.hasScheduledUpdates {
                        Text(text(
                            "并行更新 \(service.activeUpdateIDs.count) 个，排队 \(service.queuedUpdateIDs.count) 个",
                            "Updating \(service.activeUpdateIDs.count) in parallel; \(service.queuedUpdateIDs.count) queued"
                        ))
                        .font(.caption).foregroundColor(.secondary)
                    } else if let date = service.lastChecked {
                        Text(text("最近检查：", "Last checked: ") + date.formatted(date: .omitted, time: .shortened))
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField(text("搜索应用", "Search apps"), text: $query).textFieldStyle(.plain)
                }
                .padding(8).frame(width: 170)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
                Button { Task { await service.scanForUpdates() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                }
                .help(text("重新扫描", "Check again"))
                .accessibilityLabel(text("重新扫描", "Check again"))
                .disabled(service.isScanning || service.hasScheduledUpdates)
            }
            .padding(24)
            .padding(.top, 24)

            Picker(text("检测状态", "Status"), selection: $filter) {
                Text(text("全部", "All") + " (\(service.records.count))").tag(Optional<UpdateCheckState>.none)
                ForEach(UpdateCheckState.allCases, id: \.self) { state in
                    Text(title(state) + " (\(count(state)))").tag(Optional(state))
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24).padding(.bottom, 14)

            if service.isScanning {
                ProgressView(value: service.progress).progressViewStyle(.linear).tint(.cyan)
                    .padding(.horizontal, 24).padding(.bottom, 8)
            }
            Divider()
            if visibleRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: service.isScanning ? "arrow.triangle.2.circlepath" : "tray")
                        .font(.system(size: 28)).foregroundColor(.secondary)
                    Text(service.isScanning ? text("正在检查更新…", "Checking for updates…") : text("当前列表没有结果", "No results in this list"))
                        .foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleRecords) { record in
                            row(record)
                            Divider().padding(.leading, 70)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !service.scanComplete { Task { await service.scanForUpdates() } }
        }
        .alert(text("无法打开", "Cannot Open"), isPresented: Binding(get: { openError != nil }, set: { if !$0 { openError = nil } })) {
            Button(text("确定", "OK"), role: .cancel) { openError = nil }
        } message: { Text(openError ?? "") }
        .confirmationDialog(text("更新应用", "Update App"),
                            isPresented: Binding(get: { pendingUpdate != nil }, set: { if !$0 { pendingUpdate = nil } }),
                            titleVisibility: .visible, presenting: pendingUpdate) { record in
            Button(text("更新 \(record.application.name)", "Update \(record.application.name)")) {
                pendingUpdate = nil
                service.update(record)
            }
            Button(text("取消", "Cancel"), role: .cancel) { pendingUpdate = nil }
        } message: { record in
            Text(text("将 \(record.application.name) 从 \(record.application.version) 更新为 \(record.check.version)，并加入并行更新队列。如应用正在运行，将在轮到安装时请求其退出；安装时保留原版本。",
                      "Queue \(record.application.name) for a parallel update from \(record.application.version) to \(record.check.version). If it is running, it will be asked to quit when its install turn begins. The previous version will be retained."))
        }
    }

    private func installationTitle(_ phase: AppUpdateInstallPhase) -> String {
        switch phase {
        case .queued: return text("已加入更新队列", "Queued")
        case .downloading: return text("正在下载", "Downloading")
        case .unpacking: return text("正在解包", "Unpacking")
        case .verifying: return text("正在校验", "Verifying")
        case .waitingToInstall: return text("等待安装", "Waiting to install")
        case .quitting: return text("等待应用退出", "Waiting for app to quit")
        case .installing: return text("正在安装", "Installing")
        case .completed: return text("已更新，原版本已保留", "Updated; previous version retained")
        case .cancelled: return text("已取消", "Cancelled")
        case .failed: return text("更新失败", "Update failed")
        }
    }

    private func row(_ record: AppUpdateRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: record.icon).resizable().scaledToFit().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.application.name).font(.system(size: 14, weight: .medium)).lineLimit(2)
                    Spacer(minLength: 8)
                    Text(title(record.check.state)).font(.caption).foregroundColor(color(record.check.state))
                }
                HStack(spacing: 6) {
                    Text(record.application.version.isEmpty ? "?" : record.application.version)
                    if record.check.state == .available {
                        Image(systemName: "arrow.right")
                        Text(record.check.version).foregroundColor(.cyan)
                    }
                    Text("· " + record.check.source)
                }.font(.caption).foregroundColor(.secondary).textSelection(.enabled)
                    .id(record.application.version + "/" + record.application.build)
                if !record.check.message.isEmpty {
                    Text(record.check.message).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let status = service.installationStates[record.id] {
                    HStack(spacing: 6) {
                        Text(installationTitle(status.phase))
                        if let fraction = status.fraction { Text(fraction, format: .percent.precision(.fractionLength(0))) }
                    }
                    .font(.caption).foregroundColor(status.phase == .failed ? .orange : .cyan)
                    if service.activeUpdateIDs.contains(record.id) {
                        if let fraction = status.fraction { ProgressView(value: fraction).progressViewStyle(.linear).tint(.cyan) }
                    }
                    if !status.message.isEmpty {
                        Text(status.message).font(.caption).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                } else if record.check.state == .available, let reason = record.automaticUpdateUnavailableReason {
                    Text(reason).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if service.isUpdateScheduled(record.id) {
                HStack(spacing: 10) {
                    if let position = service.queuedPosition(record.id) {
                        Text(text("排队 \(position)", "Queue \(position)"))
                            .font(.caption2).foregroundColor(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Button { service.cancelUpdate(record.id) } label: { Image(systemName: "xmark") }
                        .disabled(service.installationStates[record.id]?.phase.canCancel != true)
                        .help(text("取消更新", "Cancel update"))
                        .accessibilityLabel(text("取消 \(record.application.name) 更新", "Cancel update for \(record.application.name)"))
                }.frame(width: 108, alignment: .trailing)
            } else if let backup = service.installationStates[record.id]?.backup {
                Button { NSWorkspace.shared.activateFileViewerSelecting([backup]) } label: {
                    Image(systemName: "folder").frame(width: 22, height: 22)
                }
                .frame(width: 108, alignment: .trailing)
                .help(text("查看原版本备份", "Show previous version"))
                .accessibilityLabel(text("查看 \(record.application.name) 备份", "Show backup for \(record.application.name)"))
            } else if record.check.state == .available, record.check.asset != nil, record.automaticUpdateUnavailableReason == nil {
                HStack(spacing: 8) {
                    Button { pendingUpdate = record } label: {
                        Label(text("更新", "Update"), systemImage: "arrow.down.circle").font(.caption)
                    }
                    .accessibilityLabel(text("更新 \(record.application.name)", "Update \(record.application.name)"))
                    if let url = record.check.url {
                        Button { if !NSWorkspace.shared.open(url) { openError = text("无法打开官方更新入口", "Cannot open official update page") } } label: {
                            Image(systemName: "arrow.up.right.square").font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help(text("官方更新入口", "Official update page"))
                        .accessibilityLabel(text("打开 \(record.application.name) 官方更新入口", "Open official updates for \(record.application.name)"))
                    }
                }
                .frame(width: 108, alignment: .trailing)
                .disabled(service.isScanning)
            } else if record.check.state == .available, let url = record.check.url {
                Button {
                    if !NSWorkspace.shared.open(url) { openError = text("请在应用内检查更新。", "Please check for updates in the app.") }
                } label: {
                    Label(record.check.storeID == nil ? text("官网更新", "Website") : "App Store", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .frame(width: 108, alignment: .trailing)
                .help(url.absoluteString)
                .accessibilityLabel(text("打开 \(record.application.name) 更新入口", "Open updates for \(record.application.name)"))
            } else if record.check.state == .unsupported || record.check.state == .failed {
                Button {
                    NSWorkspace.shared.openApplication(at: record.application.path, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                        if let error = error { DispatchQueue.main.async { openError = error.localizedDescription } }
                    }
                } label: {
                    Image(systemName: "arrow.up.forward.app").frame(width: 22, height: 22)
                }
                .frame(width: 108, alignment: .trailing)
                .help(text("打开应用", "Open app"))
                .accessibilityLabel(text("打开 \(record.application.name)", "Open \(record.application.name)"))
            } else {
                Color.clear.frame(width: 108, height: 1)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 15)
    }
}
