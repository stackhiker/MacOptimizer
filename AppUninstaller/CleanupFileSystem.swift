import Foundation
import Darwin

/// Logical file sizes describe the files being handled, not disk space reclaimed.
enum CleanupFileSystem {
    private struct Identity: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    static func logicalSize(at url: URL, shouldCancel: () -> Bool = { false }) -> Int64 {
        guard !shouldCancel() else { return 0 }
        var root = stat()
        guard url.path.withCString({ lstat($0, &root) }) == 0 else { return 0 }
        let kind = root.st_mode & S_IFMT
        if kind == S_IFREG { return max(0, Int64(root.st_size)) }
        guard kind == S_IFDIR else { return 0 }
        guard let entries = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        var identities = Set<Identity>()
        for case let file as URL in entries {
            if shouldCancel() { return 0 }
            var info = stat()
            guard file.path.withCString({ lstat($0, &info) }) == 0 else { continue }
            if info.st_mode & S_IFMT == S_IFLNK {
                entries.skipDescendants()
                continue
            }
            guard info.st_mode & S_IFMT == S_IFREG else { continue }
            // Most files have one link; keep memory proportional to hard-linked files.
            if info.st_nlink > 1 && !identities.insert(Identity(device: info.st_dev, inode: info.st_ino)).inserted {
                continue
            }
            let bytes = max(0, Int64(info.st_size))
            total = total > Int64.max - bytes ? Int64.max : total + bytes
        }
        return shouldCancel() ? 0 : total
    }

    static func uniqueRoots(_ urls: [URL]) -> [URL] {
        // Foundation path standardization may consult the file system. Do it
        // once per input, never inside sorting or ancestor comparisons.
        var urlsByPath: [String: URL] = [:]
        urlsByPath.reserveCapacity(urls.count)
        for url in urls {
            let normalized = url.standardizedFileURL
            let path = normalized.path
            if urlsByPath[path] == nil { urlsByPath[path] = normalized }
        }
        return uniqueRootPaths(Array(urlsByPath.keys)).compactMap { urlsByPath[$0] }
    }

    /// Deduplicates already-standardized absolute paths without any file-system
    /// access. Inputs have no trailing slash except "/". Resolve aliases before
    /// calling when required; cleanup must still revalidate each live path.
    /// Ancestor lookup is bounded by path depth, not the number of sibling items.
    static func uniqueRootPaths(_ paths: [String]) -> [String] {
        let candidates = Set(paths)
        if candidates.contains("/") { return ["/"] }

        var roots: [(path: String, length: Int)] = []
        roots.reserveCapacity(candidates.count)
        for path in candidates {
            var end = path.endIndex
            var hasAncestor = false
            while let slash = path[..<end].lastIndex(of: "/") {
                // The root case was handled above. Inspect complete path
                // components so /cache never covers /cache-other.
                if slash == path.startIndex { break }
                if candidates.contains(String(path[..<slash])) {
                    hasAncestor = true
                    break
                }
                end = slash
            }
            if !hasAncestor { roots.append((path, path.count)) }
        }
        roots.sort {
            if $0.length == $1.length { return $0.path < $1.path }
            return $0.length < $1.length
        }
        return roots.map(\.path)
    }

    static func contains(_ child: URL, in parent: URL) -> Bool {
        let childPath = child.standardizedFileURL.path
        let parentPath = parent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath == "/" ? "/" : parentPath + "/")
    }
}

/// A signed observation; concurrent system activity can also change free space.
struct CleanupDiskSnapshot {
    let volume: UInt64
    let availableBytes: Int64

    static func capture(at url: URL = FileManager.default.homeDirectoryForCurrentUser) -> CleanupDiskSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
              let volume = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else { return nil }
        return CleanupDiskSnapshot(volume: volume, availableBytes: free)
    }

    func change(since previous: CleanupDiskSnapshot?) -> Int64? {
        guard let previous, previous.volume == volume else { return nil }
        return availableBytes - previous.availableBytes
    }
}
