import Combine
import Foundation

/// Attach only services already owned by the displayed module. Observing a
/// service never starts a scan, creates another service, or adds polling.
@MainActor
final class OperationTrackingBridge {
    static let shared = OperationTrackingBridge()
    private var subscriptions: [String: [AnyCancellable]] = [:]
    private var activeRecords: [String: UUID] = [:]
    private var stopRequests = Set<String>()
    private var cancellationHandlers: [String: () -> Void] = [:]

    func attachSmart(_ service: SmartCleanerService) {
        watch(service, name: "smart-scan", title: text("智能扫描", "Smart Scan"),
            active: service.$isScanning.eraseToAnyPublisher(), progress: service.$scanProgress.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopScanning() })
        watch(service, name: "smart-clean", title: text("智能清理", "Smart Cleanup"),
            active: service.$isCleaning.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopCleaning() },
            stopped: { [weak service] in service?.cleaningWasStopped == true })
    }

    func attachJunk(_ service: JunkCleaner) {
        watch(service, name: "junk-scan", title: text("系统垃圾扫描", "System Junk Scan"),
            active: service.$isScanning.eraseToAnyPublisher(), progress: service.$scanProgress.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopScanning() },
            failed: { [weak service] in service?.hasPermissionErrors == true })
        watch(service, name: "junk-clean", title: text("系统垃圾清理", "System Junk Cleanup"),
            active: service.$isCleaning.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopCleaning() },
            stopped: { [weak service] in service?.stopCleaningRequested == true },
            failed: { [weak service] in !(service?.deletionFailures.isEmpty ?? true) })
        watch(service, name: "mail-scan", title: text("邮件附件扫描", "Mail Attachment Scan"),
            active: service.$isScanningMailAttachments.eraseToAnyPublisher(), progress: service.$mailScanProgress.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopMailAttachmentsScan() },
            failed: { [weak service] in service?.mailAttachmentsHavePermissionError == true })
        watch(service, name: "mail-clean", title: text("邮件附件清理", "Mail Attachment Cleanup"),
            active: service.$isCleaningMailAttachments.eraseToAnyPublisher(), progress: service.$mailCleaningProgress.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopMailAttachmentsCleaning() },
            stopped: { [weak service] in service?.mailCleaningWasStopped == true },
            failed: { [weak service] in !(service?.deletionFailures.isEmpty ?? true) })
    }

    func attachTrash(_ service: TrashScanner) {
        watch(service, name: "trash-scan", title: text("废纸篓扫描", "Trash Scan"),
            active: service.$isScanning.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopScan() },
            stopped: { [weak service] in service?.isStopped == true },
            failed: { [weak service] in service?.scanFailure != nil })
        watch(service, name: "trash-clean", title: text("清空废纸篓", "Empty Trash"),
            active: service.$isCleaning.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopCleaning() },
            stopped: { [weak service] in service?.cleaningWasStopped == true },
            failed: { [weak service] in (service?.failedDeletionCount ?? 0) > 0 })
    }

    func attachLarge(_ service: LargeFileScanner) {
        watch(service, name: "large-scan", title: text("大型文件扫描", "Large File Scan"),
            active: service.$isScanning.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopScan() },
            stopped: { [weak service] in service?.isStopped == true })
        watch(service, name: "large-clean", title: text("大型文件清理", "Large File Cleanup"),
            active: service.$isCleaning.eraseToAnyPublisher(), progress: service.$cleaningProgress.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopCleaning() })
    }

    func attachDeep(_ service: DeepCleanScanner, cancelCleanup: @escaping () -> Void) {
        watch(service, name: "deep-scan", title: text("深度扫描", "Deep Scan"),
            active: service.$isScanning.eraseToAnyPublisher(), progress: service.$scanProgress.eraseToAnyPublisher(),
            cancel: { [weak service] in service?.stopScan() },
            stopped: { [weak service] in service?.scanWasStopped == true })
        watch(service, name: "deep-clean", title: text("深度清理", "Deep Cleanup"),
            active: service.$isCleaning.eraseToAnyPublisher(), progress: service.$cleaningProgress.eraseToAnyPublisher(),
            cancel: cancelCleanup,
            stopped: { [weak service] in service?.lastCleanupResult?.wasStopped == true },
            failed: { [weak service] in !(service?.lastFailures.isEmpty ?? true) })
    }

    private func watch(_ service: AnyObject, name: String, title: String,
        active: AnyPublisher<Bool, Never>, progress: AnyPublisher<Double, Never>? = nil,
        cancel: @escaping () -> Void, stopped: @escaping () -> Bool = { false },
        failed: @escaping () -> Bool = { false }) {
        let key = "\(ObjectIdentifier(service))-\(name)"
        cancellationHandlers[key] = cancel
        guard subscriptions[key] == nil else { return }
        var observers: [AnyCancellable] = []
        active.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] running in
            guard let self else { return }
            if running {
                guard self.activeRecords[key] == nil else { return }
                self.stopRequests.remove(key)
                let id = OperationCenter.shared.begin(title: title) { [weak self] in
                    self?.stopRequests.insert(key)
                    self?.cancellationHandlers[key]?()
                }
                self.activeRecords[key] = id
            } else if let id = self.activeRecords.removeValue(forKey: key) {
                let cancelled = self.stopRequests.remove(key) != nil || stopped()
                OperationCenter.shared.finish(id: id,
                    state: cancelled ? .cancelled : (failed() ? .failed : .completed),
                    detail: self.text(cancelled ? "操作已停止" : "操作已结束，请查看模块结果", cancelled ? "Operation stopped" : "Finished; see the module results"))
            }
        }.store(in: &observers)
        if let progress {
            progress.receive(on: DispatchQueue.main).sink { [weak self] value in
                guard let self, let id = self.activeRecords[key] else { return }
                OperationCenter.shared.update(id: id,
                    detail: self.stopRequests.contains(key) ? self.text("正在停止…", "Stopping…") : self.text("正在处理…", "Working…"), progress: value)
            }.store(in: &observers)
        }
        subscriptions[key] = observers
    }

    private func text(_ chinese: String, _ english: String) -> String {
        LocalizationManager.shared.text(chinese, english)
    }
}
