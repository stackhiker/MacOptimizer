import Foundation
import CryptoKit
import Darwin

struct InstallationResidue: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case appBackup, codexInstallStaging, sparkleDownload, verificationTemporary, projectBackup }
    struct Identity: Hashable, Sendable {
        let device: UInt64
        let inode: UInt64
        let modifiedNanoseconds: Int64
        let changedNanoseconds: Int64
        let treeDigest: String
    }
    var id: String { url.path }
    let url: URL
    let name: String
    let size: Int64
    let kind: Kind
    let identity: Identity
}

/// Deliberately narrow rules for this app's installation artifacts. No general
/// "runtime", Library, or temporary-directory cleanup is performed here.
struct InstallationResidueScanner: Sendable {
    struct Roots: Sendable {
        let applications: URL
        let codexRuntimes: URL
        let traexCache: URL
        let temporary: URL
        let projectBackups: URL
        static let live: Roots = {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return Roots(applications: URL(fileURLWithPath: "/Applications"),
                         codexRuntimes: home.appendingPathComponent(".cache/codex-runtimes"),
                         traexCache: home.appendingPathComponent("Library/Caches/com.bytedance.local.traex.runtime"),
                         temporary: URL(fileURLWithPath: "/private/tmp"),
                         projectBackups: home.appendingPathComponent("workspace/MacOptimizer/build/backups"))
        }()
    }
    struct Budget: Sendable {
        var maximumCandidates: Int = 512
        var maximumEntries: Int = 100_000
        var timeout: TimeInterval = 20
    }
    struct ActivitySnapshot: Sendable {
        let activePaths: [String]
        let isComplete: Bool
        init(activePaths: [String], isComplete: Bool) {
            self.activePaths = activePaths.map { InstallationResidueScanner.lexicalPath($0) }
            self.isComplete = isComplete
        }
    }

    private let roots: Roots
    private let now: @Sendable () -> Date
    private let activity: (@Sendable () -> ActivitySnapshot)?
    private let minimumAge: TimeInterval
    private let budget: Budget
    private let ownerUID: UInt32

    init(roots: Roots = .live, now: @escaping @Sendable () -> Date = { Date() },
         activity: (@Sendable () -> ActivitySnapshot)? = nil,
         minimumAge: TimeInterval = 7 * 24 * 60 * 60, budget: Budget = Budget(), ownerUID: UInt32 = getuid()) {
        self.roots = roots
        self.now = now
        self.activity = activity
        self.minimumAge = max(0, minimumAge)
        self.budget = budget
        self.ownerUID = ownerUID
    }

    static let managedRootPaths: [String] = {
        let roots = Roots.live
        return [roots.codexRuntimes.path, roots.traexCache.path, roots.projectBackups.path]
    }()

    /// Pure lexical checks: safe to call while filtering or presenting results.
    /// A general cleaner must not swallow a managed root through an ancestor.
    static func excludesGenericCleanup(_ url: URL) -> Bool {
        excludesGenericCleanup(path: url.path, roots: .live)
    }

    static func excludesGenericCleanup(path: String, roots: Roots) -> Bool {
        let path = lexicalPath(path)
        for root in [roots.codexRuntimes, roots.traexCache, roots.projectBackups] {
            let managed = lexicalPath(root.path)
            if within(path, managed) || within(managed, path) { return true }
        }
        for root in [roots.applications, roots.temporary] {
            let base = lexicalPath(root.path)
            if within(base, path) { return true }
            guard within(path, base), path != base else { continue }
            let first = String(path.dropFirst(base.count + 1).split(separator: "/").first ?? "")
            if root == roots.applications ? isApplicationBackup(first) : isVerificationDirectory(first) { return true }
        }
        return false
    }

    func scan(shouldCancel: @escaping @Sendable () -> Bool = { false }) async -> [InstallationResidue] {
        let worker = Task.detached(priority: .utility) {
            scanSynchronously(shouldCancel: { shouldCancel() || Task.isCancelled })
        }
        return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
    }

    func validateForRemoval(_ candidate: InstallationResidue,
                            shouldCancel: @escaping @Sendable () -> Bool = { false }) async -> Bool {
        let worker = Task.detached(priority: .utility) {
            let cancel = { @Sendable in shouldCancel() || Task.isCancelled }
            guard !cancel(), let rule = classify(candidate.url), rule.kind == candidate.kind,
                  Self.lexicalPath(candidate.url.path) == Self.lexicalPath(candidate.url.standardizedFileURL.path),
                  (rule.kind != .projectBackup || !isRetainedProjectBackup(candidate.url)),
                  !isReferencedRuntime(candidate.url), !cancel() else { return false }
            let activity = self.activity?() ?? Self.captureActivity(shouldCancel: cancel)
            guard activity.isComplete, !cancel() else { return false }
            var remaining = budget.maximumEntries
            let deadline = ProcessInfo.processInfo.systemUptime + budget.timeout
            guard let current = inspect(candidate.url, rule: rule, activity: activity,
                                        remaining: &remaining, deadline: deadline, shouldCancel: cancel) else { return false }
            return current.identity == candidate.identity && current.size == candidate.size && !cancel()
        }
        return await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
    }

    private struct Rule { let kind: InstallationResidue.Kind; let root: URL; let isDirectory: Bool }

    private func scanSynchronously(shouldCancel: @escaping @Sendable () -> Bool) -> [InstallationResidue] {
        guard !shouldCancel() else { return [] }
        let activity = self.activity?() ?? Self.captureActivity(shouldCancel: shouldCancel)
        guard activity.isComplete, !shouldCancel() else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + budget.timeout
        var candidates: [URL] = []
        var listed = 0
        for root in [roots.applications, roots.codexRuntimes, roots.temporary, roots.projectBackups] {
            guard !shouldCancel(), ProcessInfo.processInfo.systemUptime < deadline else { return [] }
            guard Self.lexicalPath(root.path) == Self.lexicalPath(root.resolvingSymlinksInPath().path) else { continue }
            guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                listed += 1
                guard listed <= budget.maximumEntries, !shouldCancel() else { return [] }
                if classify(child) != nil {
                    candidates.append(child.standardizedFileURL)
                    if candidates.count > budget.maximumCandidates { return [] }
                }
            }
        }
        // Only the known Traex Sparkle host is managed. Unknown app cache roots
        // remain outside this feature rather than being guessed from their name.
        let downloads = roots.traexCache.appendingPathComponent("org.sparkle-project.Sparkle/PersistentDownloads")
        var pending: [(URL, Int)] = [(downloads, 0)]
        while let (directory, depth) = pending.popLast() {
            guard !shouldCancel(), ProcessInfo.processInfo.systemUptime < deadline else { return [] }
            guard Self.lexicalPath(directory.path) == Self.lexicalPath(directory.resolvingSymlinksInPath().path) else { continue }
            var info = stat()
            guard Self.metadata(directory, into: &info), info.st_mode & S_IFMT == S_IFDIR else { continue }
            guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { continue }
            for child in children {
                listed += 1
                guard listed <= budget.maximumEntries, !shouldCancel() else { return [] }
                var childInfo = stat()
                guard Self.metadata(child, into: &childInfo) else { continue }
                if childInfo.st_mode & S_IFMT == S_IFDIR, depth < 3 { pending.append((child, depth + 1)) }
                else if classify(child) != nil { candidates.append(child.standardizedFileURL) }
                if candidates.count > budget.maximumCandidates { return [] }
            }
        }
        let retained = retainedProjectBackups()
        var remaining = budget.maximumEntries
        var result: [InstallationResidue] = []
        for url in candidates.sorted(by: { $0.path < $1.path }) {
            guard !shouldCancel(), ProcessInfo.processInfo.systemUptime < deadline else { return [] }
            guard !retained.contains(Self.lexicalPath(url.path)), !isReferencedRuntime(url),
                  let rule = classify(url) else { continue }
            if let item = inspect(url, rule: rule, activity: activity, remaining: &remaining,
                                  deadline: deadline, shouldCancel: shouldCancel) { result.append(item) }
        }
        return shouldCancel() ? [] : result
    }

    /// Re-derive the rule from trusted roots and exact names; candidate metadata
    /// supplied by a caller can never expand the allowed deletion scope.
    private func classify(_ url: URL) -> Rule? {
        let path = Self.lexicalPath(url.path)
        let parent = Self.lexicalPath(url.deletingLastPathComponent().path)
        let name = url.lastPathComponent
        if parent == Self.lexicalPath(roots.applications.path), Self.isApplicationBackup(name) {
            return Rule(kind: .appBackup, root: roots.applications, isDirectory: true)
        }
        if parent == Self.lexicalPath(roots.codexRuntimes.path), Self.matches(name, "^codex-runtime-install-[A-Za-z0-9_-]+$") {
            return Rule(kind: .codexInstallStaging, root: roots.codexRuntimes, isDirectory: true)
        }
        if parent == Self.lexicalPath(roots.temporary.path), Self.isVerificationDirectory(name) {
            return Rule(kind: .verificationTemporary, root: roots.temporary, isDirectory: true)
        }
        if parent == Self.lexicalPath(roots.projectBackups.path), Self.isProjectBackup(name) {
            return Rule(kind: .projectBackup, root: roots.projectBackups, isDirectory: false)
        }
        let downloads = roots.traexCache.appendingPathComponent("org.sparkle-project.Sparkle/PersistentDownloads")
        let downloadsPath = Self.lexicalPath(downloads.path)
        if Self.within(path, downloadsPath), path != downloadsPath,
           path.dropFirst(downloadsPath.count + 1).split(separator: "/").count <= 4,
           ["zip", "dmg", "pkg"].contains(url.pathExtension.lowercased()) {
            return Rule(kind: .sparkleDownload, root: roots.traexCache, isDirectory: false)
        }
        return nil
    }

    private func inspect(_ url: URL, rule: Rule, activity: ActivitySnapshot, remaining: inout Int,
                         deadline: TimeInterval, shouldCancel: @escaping @Sendable () -> Bool) -> InstallationResidue? {
        let path = url.path
        let activityPath = Self.lexicalPath(path)
        guard activityPath == Self.lexicalPath(url.standardizedFileURL.path),
              Self.lexicalPath(rule.root.path) == Self.lexicalPath(rule.root.resolvingSymlinksInPath().path),
              activityPath == Self.lexicalPath(url.resolvingSymlinksInPath().path),
              !activity.activePaths.contains(where: { Self.within($0, activityPath) }) else { return nil }
        var rootInfo = stat()
        guard Self.metadata(url, into: &rootInfo), eligible(rootInfo),
              rootInfo.st_mode & S_IFMT == (rule.isDirectory ? S_IFDIR : S_IFREG) else { return nil }
        let cutoff = now().timeIntervalSince1970 - minimumAge
        var records: [String] = []
        var size: Int64 = 0
        func add(_ entry: URL, _ info: stat) -> Bool {
            remaining -= 1
            guard remaining >= 0, !shouldCancel(), ProcessInfo.processInfo.systemUptime < deadline,
                  eligible(info), Double(info.st_mtimespec.tv_sec) <= cutoff,
                  Double(info.st_ctimespec.tv_sec) <= cutoff else { return false }
            let kind = info.st_mode & S_IFMT
            guard kind == S_IFREG || kind == S_IFDIR || kind == S_IFLNK else { return false }
            var linkTarget = ""
            if kind == S_IFLNK {
                guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path) else { return false }
                let targetURL = target.hasPrefix("/") ? URL(fileURLWithPath: target)
                    : entry.deletingLastPathComponent().appendingPathComponent(target)
                let resolved = targetURL.standardizedFileURL.resolvingSymlinksInPath()
                var targetInfo = stat()
                guard Self.within(Self.lexicalPath(resolved.path), activityPath), Self.metadata(resolved, into: &targetInfo),
                      targetInfo.st_mode & S_IFMT != S_IFLNK else { return false }
                linkTarget = target
            }
            if kind == S_IFREG {
                let bytes = max(0, Int64(info.st_size))
                guard size <= Int64.max - bytes else { return false }
                size += bytes
            }
            let relative = String(Self.lexicalPath(entry.path).dropFirst(activityPath.count))
            records.append("\(relative)\u{0}\(info.st_dev):\(info.st_ino):\(info.st_mode):\(info.st_uid):\(info.st_size):\(Self.modified(info)):\(Self.changed(info))\u{0}\(linkTarget)")
            return true
        }
        guard add(url, rootInfo) else { return nil }
        if rule.isDirectory {
            // Walk packages explicitly. App/framework bundles must contribute all
            // regular files, while internal links are inspected but never followed.
            var pending = [url]
            while let directory = pending.popLast() {
                guard !shouldCancel(), ProcessInfo.processInfo.systemUptime < deadline,
                      let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
                for entry in children {
                    var info = stat()
                    guard Self.metadata(entry, into: &info), info.st_dev == rootInfo.st_dev, add(entry, info) else { return nil }
                    if info.st_mode & S_IFMT == S_IFDIR { pending.append(entry) }
                }
            }
        }
        // Detect a replacement/change while collecting the tree snapshot.
        var finalInfo = stat()
        guard Self.metadata(url, into: &finalInfo), Self.sameRoot(rootInfo, finalInfo), !shouldCancel() else { return nil }
        var digest = SHA256()
        for record in records.sorted() {
            let data = Data(record.utf8)
            digest.update(data: Data("\(data.count):".utf8))
            digest.update(data: data)
        }
        return InstallationResidue(url: url, name: url.lastPathComponent, size: size, kind: rule.kind,
              identity: .init(device: UInt64(bitPattern: Int64(rootInfo.st_dev)), inode: UInt64(rootInfo.st_ino),
                              modifiedNanoseconds: Self.modified(rootInfo), changedNanoseconds: Self.changed(rootInfo),
                              treeDigest: digest.finalize().map { String(format: "%02x", $0) }.joined()))
    }

    private func eligible(_ info: stat) -> Bool {
        info.st_uid == ownerUID
    }
    private static func metadata(_ url: URL, into info: inout stat) -> Bool { url.path.withCString { lstat($0, &info) } == 0 }
    private static func modified(_ s: stat) -> Int64 { Int64(s.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(s.st_mtimespec.tv_nsec) }
    private static func changed(_ s: stat) -> Int64 { Int64(s.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(s.st_ctimespec.tv_nsec) }
    private static func sameRoot(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_uid == b.st_uid && a.st_mode == b.st_mode && modified(a) == modified(b) && changed(a) == changed(b)
    }
    private func retainedProjectBackups() -> Set<String> {
        guard Self.lexicalPath(roots.projectBackups.path) == Self.lexicalPath(roots.projectBackups.resolvingSymlinksInPath().path) else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(at: roots.projectBackups, includingPropertiesForKeys: nil) else { return [] }
        let backups = files.compactMap { url -> (URL, Int64)? in
            var info = stat()
            guard Self.isProjectBackup(url.lastPathComponent), Self.metadata(url, into: &info),
                  info.st_mode & S_IFMT == S_IFREG, info.st_uid == ownerUID else { return nil }
            return (url, Self.modified(info))
        }.sorted { $0.1 == $1.1 ? $0.0.lastPathComponent > $1.0.lastPathComponent : $0.1 > $1.1 }
        return Set(backups.prefix(1).map { Self.lexicalPath($0.0.path) })
    }
    private func isRetainedProjectBackup(_ url: URL) -> Bool { retainedProjectBackups().contains(Self.lexicalPath(url.path)) }

    /// A current runtime alias can point into staging even while no process is
    /// running. Keep its target rather than inferring obsolescence from age alone.
    private func isReferencedRuntime(_ url: URL) -> Bool {
        guard Self.lexicalPath(url.deletingLastPathComponent().path) == Self.lexicalPath(roots.codexRuntimes.path) else { return false }
        guard let siblings = try? FileManager.default.contentsOfDirectory(at: roots.codexRuntimes, includingPropertiesForKeys: nil),
              siblings.count <= budget.maximumEntries else { return true }
        return siblings.contains { sibling in
            var info = stat()
            guard Self.metadata(sibling, into: &info), info.st_mode & S_IFMT == S_IFLNK else { return false }
            let target = Self.lexicalPath(sibling.resolvingSymlinksInPath().path)
            return Self.within(target, Self.lexicalPath(url.path))
        }
    }
    private static func within(_ path: String, _ root: String) -> Bool { path == root || path.hasPrefix(root == "/" ? "/" : root + "/") }
    private static func lexicalPath(_ path: String) -> String {
        if path == "/tmp" || path.hasPrefix("/tmp/") { return "/private" + path }
        if path == "/var" || path.hasPrefix("/var/") { return "/private" + path }
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func isApplicationBackup(_ name: String) -> Bool {
        if name.hasPrefix(".MacOptimizer-Update-"), UUID(uuidString: String(name.dropFirst(".MacOptimizer-Update-".count))) != nil { return true }
        return matches(name, "^\\.Traex(?:-test)?\\.app(?:\\.runtime)?\\.backup\\.[0-9]+$")
    }
    private static func isProjectBackup(_ name: String) -> Bool { matches(name, "^MacOptimizer_v[0-9.]+_build[0-9]+_before_build[0-9]+_[0-9]{8}T[0-9]{6}Z\\.zip$") }
    private static func isVerificationDirectory(_ name: String) -> Bool {
        let exact: Set<String> = ["macoptimizer-memory-test-build", "macoptimizer-deepclean-validation", "macoptimizer-memory-test-package", "macoptimizer-memory-module-cache", "macoptimizer-monitor-probe", "macoptimizer-audit-module-cache", "macoptimizer-memory-spm-cache"]
        return exact.contains(name) || matches(name, "^macoptimizer-(?:cleanup-fix|audit|disk-safety-audit)-[A-Za-z0-9_]+$") || matches(name, "^macoptimizer-(?:responsiveness|install-residue)-[0-9]{8}$")
    }

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        private var exceeded = false
        func append(_ data: Data) { lock.lock(); defer { lock.unlock() }; if bytes.count + data.count <= 16 * 1024 * 1024 { bytes.append(data) } else { exceeded = true } }
        func result() -> (Data, Bool) { lock.lock(); defer { lock.unlock() }; return (bytes, exceeded) }
    }

    /// One bounded activity snapshot per scan, fresh again before removal.
    /// Output and errors are drained concurrently; incomplete observations fail closed.
    static func captureActivity(shouldCancel: @escaping @Sendable () -> Bool = { false }) -> ActivitySnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-F", "pn"]
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output; process.standardError = errors
        do { try process.run() } catch { return ActivitySnapshot(activePaths: [], isComplete: false) }
        let buffers = [OutputBuffer(), OutputBuffer()]
        let readers = DispatchGroup()
        for (index, pipe) in [output, errors].enumerated() {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { readers.leave() }
                while let data = try? pipe.fileHandleForReading.read(upToCount: 64 * 1024), !data.isEmpty { buffers[index].append(data) }
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 8
        while process.isRunning && !shouldCancel() && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let interrupted = process.isRunning
        if interrupted { process.terminate(); Thread.sleep(forTimeInterval: 0.05); if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        guard readers.wait(timeout: .now() + 1) == .success, !process.isRunning else { return ActivitySnapshot(activePaths: [], isComplete: false) }
        process.waitUntilExit()
        let (data, truncated) = buffers[0].result(), (errorData, errorTruncated) = buffers[1].result()
        let complete = !interrupted && !shouldCancel() && process.terminationStatus == 0 && !truncated && !errorTruncated && errorData.isEmpty
        let paths = String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("n/") else { return nil }
            return String(line.dropFirst())
        }
        return ActivitySnapshot(activePaths: paths, isComplete: complete)
    }
}
