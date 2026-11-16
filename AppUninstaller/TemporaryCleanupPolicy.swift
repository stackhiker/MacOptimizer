import Foundation
import Darwin

/// Automatic cleanup only considers old files directly inside a temporary root.
/// A directory may belong to an active build, download or application session.
enum TemporaryCleanupPolicy {
    static let minimumAge: TimeInterval = 14 * 24 * 60 * 60

    static var roots: [URL] {
        let userRoot = URL(fileURLWithPath: NSTemporaryDirectory()).deletingLastPathComponent()
        return CleanupFileSystem.uniqueRoots([
            userRoot.appendingPathComponent("T"), userRoot.appendingPathComponent("C"),
            URL(fileURLWithPath: "/tmp"), URL(fileURLWithPath: "/private/var/tmp")
        ])
    }

    static func temporaryRoot(containing url: URL) -> URL? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let root = roots.first(where: {
            let rootPath = $0.standardizedFileURL.resolvingSymlinksInPath().path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }) { return root }
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        let prefix = home + "/Library/Containers/"
        if path.hasPrefix(prefix), let range = path.range(of: "/Data/tmp", range: path.index(path.startIndex, offsetBy: prefix.count)..<path.endIndex) {
            let rootPath = String(path[..<range.upperBound])
            if path == rootPath || path.hasPrefix(rootPath + "/") { return URL(fileURLWithPath: rootPath) }
        }
        return nil
    }

    static func isEligible(_ url: URL, in root: URL, now: Date = Date()) -> Bool {
        let normalized = url.standardizedFileURL
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard normalized.deletingLastPathComponent().resolvingSymlinksInPath().path == rootPath,
              let values = try? normalized.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .contentAccessDateKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              let modified = values.contentModificationDate, let accessed = values.contentAccessDate,
              now.timeIntervalSince(modified) >= minimumAge,
              now.timeIntervalSince(accessed) >= minimumAge,
              let attributes = try? FileManager.default.attributesOfItem(atPath: normalized.path),
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.referenceCount] as? NSNumber)?.intValue == 1 else { return false }
        return true
    }

    static func eligibleFiles(in root: URL, now: Date = Date(), shouldCancel: () -> Bool = { false }) -> [URL] {
        guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .contentAccessDateKey]) else { return [] }
        var result: [URL] = []
        for child in children {
            if shouldCancel() { break }
            if isEligible(child, in: root, now: now) { result.append(child) }
        }
        return result
    }
}
