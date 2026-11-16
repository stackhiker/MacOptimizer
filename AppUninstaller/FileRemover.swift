import Foundation
import AppKit

// MARK: - 文件删除服务
// Stored callbacks are immutable and are invoked only on removalQueue.
final class FileRemover: @unchecked Sendable {
    private let trashItem: ((URL) throws -> Void)?
    private let removeItem: (URL) throws -> Void
    private let recordFailure: (RemovalFailure) -> Void

    init(trashItem: ((URL) throws -> Void)? = nil, removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
         recordFailure: @escaping (RemovalFailure) -> Void = {
             DeletionLogService.shared.logFailure($0, category: "AppUninstall")
         }) {
        self.trashItem = trashItem
        self.removeItem = removeItem
        self.recordFailure = recordFailure
    }
    
    // Serialize destructive I/O across views and remover instances. No file
    // traversal, Trash operation or journal write runs on the main thread.
    private static let removalQueue = DispatchQueue(label: "com.macoptimizer.uninstall-removal", qos: .userInitiated)

    /// Remove the bundle first. If it cannot be removed, preserve all app data.
    func removeApp(_ app: InstalledApp, includeApp: Bool = true, moveToTrash: Bool = true) async -> RemovalResult {
        let snapshot = await MainActor.run { () -> ([(URL, Int64)], URL?) in
            var paths: [(URL, Int64)] = []
            if includeApp { paths.append((app.path, app.size)) }
            paths.append(contentsOf: app.residualFiles.filter(\.isSelected).map { ($0.path, $0.size) })
            return (paths, includeApp ? app.path : nil)
        }
        return await enqueueRemoval(snapshot.0, appPath: snapshot.1, moveToTrash: moveToTrash)
    }

    func removeResidualFiles(of app: InstalledApp, moveToTrash: Bool = true) async -> RemovalResult {
        await removeApp(app, includeApp: false, moveToTrash: moveToTrash)
    }

    func removePaths(_ paths: [(URL, Int64)], moveToTrash: Bool = true) async -> RemovalResult {
        await enqueueRemoval(paths, appPath: nil, moveToTrash: moveToTrash)
    }

    private func enqueueRemoval(_ paths: [(URL, Int64)], appPath: URL?, moveToTrash: Bool) async -> RemovalResult {
        let cancellation = RemovalCancellation()
        return await withTaskCancellationHandler {
            if Task.isCancelled { cancellation.cancel() }
            return await withCheckedContinuation { continuation in
                Self.removalQueue.async {
                    continuation.resume(returning: self.removeItems(paths, appPath: appPath,
                        moveToTrash: moveToTrash, cancellation: cancellation))
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func removeItems(_ paths: [(URL, Int64)], appPath: URL?, moveToTrash: Bool,
                             cancellation: RemovalCancellation) -> RemovalResult {
        var successCount = 0
        var totalSizeRemoved: Int64 = 0
        var completedPaths: [URL] = []
        var failures: [RemovalFailure] = []
        var seenPaths = Set<String>()

        for (path, size) in paths where seenPaths.insert(path.standardizedFileURL.path).inserted {
            // Unattempted items are retained, not deletion failures. In
            // particular, stopping a large batch must not write one journal
            // entry per untouched path.
            if cancellation.isCancelled { break }
            do {
                if moveToTrash {
                    if let trashItem { try trashItem(path) }
                    else { try DeletionLogService.shared.trashItem(at: path, category: "AppUninstall", sizeHint: size) }
                } else { try removeItem(path) }
                successCount += 1
                totalSizeRemoved += size
                completedPaths.append(path)
            } catch {
                let error = error as NSError
                if ((error.domain == NSCocoaErrorDomain &&
                    [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)) ||
                    (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))) &&
                    targetIsMissing(path) {
                    completedPaths.append(path)
                } else {
                    let failure = RemovalFailure(path: path, error: error)
                    failures.append(failure)
                    recordFailure(failure)
                    if path.standardizedFileURL == appPath?.standardizedFileURL {
                        break
                    }
                }
            }
        }

        return RemovalResult(successCount: successCount, totalSizeRemoved: totalSizeRemoved,
            completedPaths: completedPaths, failures: failures,
            appRemoved: appPath.map { appPath in
                completedPaths.contains { $0.standardizedFileURL == appPath.standardizedFileURL }
            } ?? false)
    }

    private func targetIsMissing(_ path: URL) -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: path.path)
            return false
        } catch {
            let error = error as NSError
            return (error.domain == NSCocoaErrorDomain &&
                    [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)) ||
                (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
        }
    }
    
    /// 检查应用是否正在运行
    func isAppRunning(_ app: InstalledApp) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        
        // 通过Bundle ID匹配
        if let bundleId = app.bundleIdentifier {
            if runningApps.contains(where: { $0.bundleIdentifier == bundleId }) {
                return true
            }
        }
        
        // 通过路径匹配
        if runningApps.contains(where: { $0.bundleURL == app.path }) {
            return true
        }
        
        return false
    }
    
    /// 尝试终止应用
    func terminateApp(_ app: InstalledApp) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for runningApp in runningApps {
            if runningApp.bundleIdentifier == app.bundleIdentifier || runningApp.bundleURL == app.path {
                return runningApp.terminate()
            }
        }
        
        return false
    }
    
    /// 强制终止应用
    func forceTerminateApp(_ app: InstalledApp) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for runningApp in runningApps {
            if runningApp.bundleIdentifier == app.bundleIdentifier || runningApp.bundleURL == app.path {
                return runningApp.forceTerminate()
            }
        }
        
        return false
    }
    
    /// Termination uses the running application identity, without shell matching.
    func forceTerminateAppWithPrivilege(_ app: InstalledApp) async -> Bool {
        forceTerminateApp(app)
    }
}

private final class RemovalCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
