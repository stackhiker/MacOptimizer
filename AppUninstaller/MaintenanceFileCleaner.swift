import Foundation
import Darwin

/// Maintenance only considers aged regular cache files or diagnostic reports.
/// Moving to Trash is reversible; these bytes are never reported as freed disk space.
struct MaintenanceFileCleaner {
    enum Kind { case cache, diagnosticReports }
    struct Result {
        var movedCount = 0
        var movedBytes: Int64 = 0
        var failures: [String] = []
        var cancelled = false
    }

    var now: Date = Date()
    var minimumAge: TimeInterval = 30 * 24 * 60 * 60
    var isOwnerRunning: (String) -> Bool = { _ in false }
    var isSafe: (URL) -> Bool = { SafetyGuard.shared.isSafeToDelete($0) }
    var moveToTrash: (URL) throws -> Void = { try DeletionLogService.shared.trashItem(at: $0, category: "Maintenance") }

    func eligibleSize(_ url: URL, under root: URL, kind: Kind) -> Int64? {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/"),
              url.resolvingSymlinksInPath().path == path else { return nil }
        let relative = String(path.dropFirst(rootPath.count + 1))
        let components = relative.split(separator: "/").map(String.init)
        switch kind {
        case .cache:
            // Only recognisable per-app cache roots. Unknown cache layouts stay untouched.
            guard components.count >= 2, components[0].contains("."),
                  !components[0].hasPrefix("com.apple."), !isOwnerRunning(components[0]),
                  ["cache", "tmp", "log"].contains(url.pathExtension.lowercased()) else { return nil }
        case .diagnosticReports:
            guard components.count == 1, ["crash", "ips"].contains(url.pathExtension.lowercased()) else { return nil }
        }
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else { return nil }
        let cutoff = now.addingTimeInterval(-minimumAge).timeIntervalSince1970
        guard info.st_mtimespec.tv_sec > 0, info.st_atimespec.tv_sec > 0,
              Double(info.st_mtimespec.tv_sec) < cutoff,
              Double(info.st_atimespec.tv_sec) < cutoff,
              isSafe(url) else { return nil }
        return max(0, info.st_size)
    }

    func clean(root: URL, kind: Kind, isCancelled: () -> Bool = { Task.isCancelled }) -> Result {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var result = Result()
        // Do not follow a replaced/symlinked cleanup root.
        guard root.standardizedFileURL.path == canonicalRoot.path else {
            result.failures.append(root.path + ": symbolic-link root was skipped")
            return result
        }
        var rootInfo = stat()
        guard lstat(root.path, &rootInfo) == 0 else {
            if errno != ENOENT { result.failures.append(root.path + ": " + String(cString: strerror(errno))) }
            return result
        }
        guard rootInfo.st_mode & S_IFMT == S_IFDIR else {
            result.failures.append(root.path + ": not a directory")
            return result
        }
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, error in result.failures.append(url.path + ": " + error.localizedDescription); return true }) else {
            result.failures.append(root.path + ": cannot read directory")
            return result
        }
        while let url = enumerator.nextObject() as? URL {
            if isCancelled() { result.cancelled = true; break }
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                enumerator.skipDescendants()
                continue
            }
            guard let size = eligibleSize(url, under: root, kind: kind) else { continue }
            // Recheck immediately before mutation: recent files and newly running apps are retained.
            guard !isCancelled(), eligibleSize(url, under: root, kind: kind) == size else { continue }
            do {
                try moveToTrash(url)
                result.movedCount += 1
                result.movedBytes += size
            } catch {
                result.failures.append(url.path + ": " + error.localizedDescription)
            }
        }
        return result
    }
}
