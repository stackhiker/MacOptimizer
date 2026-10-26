import Foundation
import AppKit

// MARK: - 文件删除服务
class FileRemover {
    private let trashItem: (URL) throws -> Void
    private let removeItem: (URL) throws -> Void
    private let recordFailure: (RemovalFailure) -> Void

    init(trashItem: @escaping (URL) throws -> Void = {
        try DeletionLogService.shared.trashItem(at: $0, category: "AppUninstall")
    }, removeItem: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
         recordFailure: @escaping (RemovalFailure) -> Void = {
             DeletionLogService.shared.logFailure($0, category: "AppUninstall")
         }) {
        self.trashItem = trashItem
        self.removeItem = removeItem
        self.recordFailure = recordFailure
    }
    
    /// 删除应用及其残留文件
    func removeApp(_ app: InstalledApp, includeApp: Bool = true, moveToTrash: Bool = true) async -> RemovalResult {
        // 收集所有需要删除的路径
        var pathsToDelete: [(URL, Int64)] = []
        
        for file in app.residualFiles where file.isSelected {
            pathsToDelete.append((file.path, file.size))
        }
        
        if includeApp {
            pathsToDelete.append((app.path, app.size))
        }
        
        return removeItems(pathsToDelete, appPath: includeApp ? app.path : nil, moveToTrash: moveToTrash)
    }
    
    /// 仅删除残留文件（保留应用本体）
    func removeResidualFiles(of app: InstalledApp, moveToTrash: Bool = true) async -> RemovalResult {
        await removeApp(app, includeApp: false, moveToTrash: moveToTrash)
    }

    private func removeItems(_ paths: [(URL, Int64)], appPath: URL?, moveToTrash: Bool) -> RemovalResult {
        var successCount = 0
        var totalSizeRemoved: Int64 = 0
        var completedPaths: [URL] = []
        var failures: [RemovalFailure] = []
        var seenPaths = Set<String>()

        for (path, size) in paths where seenPaths.insert(path.standardizedFileURL.path).inserted {
            do {
                if moveToTrash { try trashItem(path) }
                else { try removeItem(path) }
                successCount += 1
                totalSizeRemoved += size
                completedPaths.append(path)
            } catch {
                let error = error as NSError
                // An earlier attempt or removal of a parent may already have
                // removed this target. Do not count its size a second time.
                if ((error.domain == NSCocoaErrorDomain &&
                    [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)) ||
                    (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))) &&
                    targetIsMissing(path) {
                    completedPaths.append(path)
                } else {
                    let failure = RemovalFailure(path: path, error: error)
                    failures.append(failure)
                    recordFailure(failure)
                }
            }
        }

        return RemovalResult(
            successCount: successCount,
            totalSizeRemoved: totalSizeRemoved,
            completedPaths: completedPaths,
            failures: failures,
            appRemoved: appPath.map { appPath in
                completedPaths.contains { $0.standardizedFileURL == appPath.standardizedFileURL }
            } ?? false
        )
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
