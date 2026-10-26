import Foundation
import AppKit
import Security
import CryptoKit
import Darwin

enum AppUpdateInstallError: Error, LocalizedError {
    case rejected(String)
    var errorDescription: String? {
        if case .rejected(let message) = self { return message }
        return nil
    }
}

enum AppUpdateInstallPhase: Sendable, Equatable {
    case queued, downloading, unpacking, verifying, waitingToInstall, quitting, installing, completed, cancelled, failed
    var canCancel: Bool {
        switch self {
        case .queued, .downloading, .unpacking, .verifying, .waitingToInstall, .quitting:
            return true
        case .installing, .completed, .cancelled, .failed:
            return false
        }
    }
}

struct AppUpdateInstallStatus: Sendable {
    var phase: AppUpdateInstallPhase
    var fraction: Double? = nil
    var message = ""
    var backup: URL? = nil
}

struct PreparedAppUpdate: Sendable {
    let application: UpdateApplication
    let asset: AppUpdateAsset
    let directory: URL
    let bundle: URL
}

// Each installation is serialized; the UI owns cancellation and application quit requests.
actor AppUpdateInstaller {
    typealias Progress = @Sendable (AppUpdateInstallStatus) -> Void
    typealias Download = @Sendable (URL, URL, @escaping @Sendable (Double) -> Void) async throws -> Void
    typealias Verify = @Sendable (URL, UpdateApplication, AppUpdateAsset, URL) throws -> Void
    private let roots: [URL]
    private let download: Download
    private let verify: Verify
    private let isRunning: @Sendable (UpdateApplication) -> Bool
    private let manager = FileManager.default

    init(roots: [URL] = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")],
         download: @escaping Download = { url, destination, progress in
             try await AppUpdateDownload().start(url: url, destination: destination, progress: progress)
         }, verify: @escaping Verify = { try AppUpdateVerifier.validate($0, application: $1, asset: $2, original: $3) },
         isRunning: @escaping @Sendable (UpdateApplication) -> Bool = { app in
             let path = app.path.resolvingSymlinksInPath()
             return NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).contains {
                 $0.bundleURL?.resolvingSymlinksInPath() == path && !$0.isTerminated
             }
         }) {
        self.roots = roots
        self.download = download
        self.verify = verify
        self.isRunning = isRunning
    }

    nonisolated static func unavailableReason(for app: UpdateApplication, check: UpdateCheck) -> String? {
        if app.isAppStore { return "请通过 App Store 更新" }
        if app.bundleID == Bundle.main.bundleIdentifier { return "请通过官网更新本应用" }
        if app.isHomebrewManaged { return "此应用由 Homebrew 管理，请通过原安装渠道更新" }
        guard check.asset != nil else { return "此更新需要使用官方安装程序" }
        guard AppUpdateVerifier.teamIdentifier(at: app.path) != nil else { return "无法确认原应用的开发者签名，请使用官方更新" }
        guard FileManager.default.isWritableFile(atPath: app.path.deletingLastPathComponent().path) else {
            return "没有安装目录的写入权限，请使用官方安装程序"
        }
        return nil
    }

    func prepare(application: UpdateApplication, asset: AppUpdateAsset, progress: @escaping Progress) async throws -> PreparedAppUpdate {
        try validateDestination(application)
        let directory = manager.temporaryDirectory.appendingPathComponent("MacOptimizerUpdate-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            let archive = directory.appendingPathComponent("download.\(asset.format.rawValue)")
            progress(.init(phase: .downloading, fraction: 0))
            try await download(asset.url, archive) { progress(.init(phase: .downloading, fraction: $0)) }
            try Task.checkCancellation()
            progress(.init(phase: .verifying))
            try AppUpdateVerifier.verifyArchive(archive, asset: asset)
            try Task.checkCancellation()
            progress(.init(phase: .unpacking))
            let bundle = try unpack(archive, asset: asset, directory: directory, bundleID: application.bundleID)
            try Task.checkCancellation()
            progress(.init(phase: .verifying))
            try verify(bundle, application, asset, application.path)
            try Task.checkCancellation()
            return PreparedAppUpdate(application: application, asset: asset, directory: directory, bundle: bundle)
        } catch {
            cleanup(directory)
            throw error
        }
    }

    func discard(_ prepared: PreparedAppUpdate) { cleanup(prepared.directory) }

    func install(_ prepared: PreparedAppUpdate, progress: @escaping Progress) throws -> URL {
        defer { cleanup(prepared.directory) }
        try Task.checkCancellation()
        try validateDestination(prepared.application)
        let target = prepared.application.path
        let transaction = target.deletingLastPathComponent().appendingPathComponent(".MacOptimizer-Update-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: transaction, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let staged = transaction.appendingPathComponent("New.app")
        let backup = transaction.appendingPathComponent(target.lastPathComponent)
        var oldMoved = false
        var newMoved = false
        do {
            progress(.init(phase: .installing))
            _ = try AppUpdateCommand.run("/usr/bin/ditto", [prepared.bundle.path, staged.path], timeout: 600)
            try verify(staged, prepared.application, prepared.asset, target)
            try validateDestination(prepared.application)
            guard !isRunning(prepared.application) else {
                throw AppUpdateInstallError.rejected("应用已重新打开，请退出应用后重试")
            }
            try Task.checkCancellation()
            // Both renames stay on the destination volume. The original is retained until validation succeeds.
            try manager.moveItem(at: target, to: backup)
            oldMoved = true
            try manager.moveItem(at: staged, to: target)
            newMoved = true
            try verify(target, prepared.application, prepared.asset, backup)
            return backup
        } catch {
            if oldMoved {
                do {
                    if newMoved {
                        try manager.moveItem(at: target, to: transaction.appendingPathComponent("Rejected.app"))
                    }
                    try manager.moveItem(at: backup, to: target)
                } catch {
                    throw AppUpdateInstallError.rejected("更新未完成，自动恢复失败。原应用保留在：\(backup.path)。错误：\(error.localizedDescription)")
                }
                throw AppUpdateInstallError.rejected("更新未完成，已恢复原应用。\(error.localizedDescription)")
            }
            try? manager.removeItem(at: transaction)
            throw error
        }
    }

    private func validateDestination(_ application: UpdateApplication) throws {
        let target = application.path.standardizedFileURL
        let parent = target.deletingLastPathComponent()
        guard target.pathExtension == "app", roots.contains(where: { $0.standardizedFileURL == parent }),
              target.resolvingSymlinksInPath() == target,
              let installed = UpdateApplication.read(at: target), installed.bundleID == application.bundleID,
              installed.version == application.version, installed.build == application.build,
              !installed.isAppStore, !installed.isHomebrewManaged else {
            throw AppUpdateInstallError.rejected("应用位置、版本或安装渠道已变化，请重新扫描后更新")
        }
        guard manager.isWritableFile(atPath: parent.path) else {
            throw AppUpdateInstallError.rejected("没有安装目录的写入权限，请使用官方安装程序")
        }
    }

    private func unpack(_ archive: URL, asset: AppUpdateAsset, directory: URL, bundleID: String) throws -> URL {
        let diskImage: Bool
        if asset.format == .archive { diskImage = try isDiskImage(archive) }
        else { diskImage = asset.format == .dmg }
        if !diskImage {
            let list = try AppUpdateCommand.run("/usr/bin/tar", ["-tf", archive.path])
            let paths = String(decoding: list, as: UTF8.self).split(separator: "\n").map(String.init)
            guard !paths.isEmpty, paths.allSatisfy(Self.safeArchivePath) else {
                throw AppUpdateInstallError.rejected("更新压缩包包含不安全的路径")
            }
            let contents = directory.appendingPathComponent("Contents", isDirectory: true)
            try manager.createDirectory(at: contents, withIntermediateDirectories: false)
            // bsdtar's default extraction rejects parent traversal and intervening symlinks.
            _ = try AppUpdateCommand.run("/usr/bin/tar", ["-xf", archive.path, "-C", contents.path, "--no-same-owner"], timeout: 600)
            return try findBundle(in: contents, bundleID: bundleID)
        } else {
            let mount = directory.appendingPathComponent("Mounted", isDirectory: true)
            try manager.createDirectory(at: mount, withIntermediateDirectories: false)
            _ = try AppUpdateCommand.run("/usr/bin/hdiutil", ["attach", archive.path, "-readonly", "-nobrowse", "-noautoopen", "-owners", "off", "-mountpoint", mount.path, "-plist"])
            let source = try findBundle(in: mount, bundleID: bundleID)
            let candidate = directory.appendingPathComponent("Ready.app")
            _ = try AppUpdateCommand.run("/usr/bin/ditto", [source.path, candidate.path], timeout: 600)
            _ = try AppUpdateCommand.run("/usr/bin/hdiutil", ["detach", mount.path], timeout: 30)
            return candidate
        }
    }

    private func isDiskImage(_ archive: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size >= 512 else { return false }
        try handle.seek(toOffset: size - 512)
        return try handle.read(upToCount: 4) == Data("koly".utf8)
    }

    nonisolated static func safeArchivePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\\") &&
        !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
        !path.split(separator: "/").contains("..")
    }

    private func findBundle(in root: URL, bundleID: String) throws -> URL {
        var matches: [URL] = []
        func visit(_ directory: URL, depth: Int) throws {
            guard depth < 5 else { return }
            for url in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values.isSymbolicLink != true, values.isDirectory == true else { continue }
                if url.pathExtension == "app" {
                    if UpdateApplication.read(at: url)?.bundleID == bundleID { matches.append(url) }
                } else if url.pathExtension != "pkg" {
                    try visit(url, depth: depth + 1)
                }
            }
        }
        try visit(root, depth: 0)
        guard matches.count == 1 else { throw AppUpdateInstallError.rejected("更新包中没有唯一匹配的应用，请使用官方安装程序") }
        return matches[0]
    }

    private func cleanup(_ directory: URL) {
        let mount = directory.appendingPathComponent("Mounted")
        if manager.fileExists(atPath: mount.path) {
            let mounted = manager.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
            if mounted.contains(where: { $0.resolvingSymlinksInPath() == mount.resolvingSymlinksInPath() }) {
                guard (try? AppUpdateCommand.run("/usr/bin/hdiutil", ["detach", mount.path], timeout: 30)) != nil else { return }
            }
        }
        try? manager.removeItem(at: directory)
    }
}

enum AppUpdateVerifier {
    static func teamIdentifier(at url: URL) -> String? {
        guard let code = staticCode(url) else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty else { return nil }
        return team
    }

    static func validate(_ candidate: URL, application: UpdateApplication, asset: AppUpdateAsset, original: URL) throws {
        try validateMetadata(candidate, application: application, asset: asset)
        guard let installed = staticCode(original), let code = staticCode(candidate),
              let team = teamIdentifier(at: original), teamIdentifier(at: candidate) == team else {
            throw AppUpdateInstallError.rejected("更新应用的开发者身份与原应用不一致")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        var requirement: SecRequirement?
        guard SecStaticCodeCheckValidity(installed, flags, nil) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(installed, [], &requirement) == errSecSuccess,
              let requirement = requirement,
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else {
            throw AppUpdateInstallError.rejected("应用签名校验失败，已停止安装")
        }
        let value = "0083;\(String(Int(Date().timeIntervalSince1970), radix: 16));MacOptimizer;\(UUID().uuidString)"
        let result = value.withCString { bytes in
            setxattr(candidate.path, "com.apple.quarantine", bytes, strlen(bytes), 0, 0)
        }
        guard result == 0 else { throw AppUpdateInstallError.rejected("无法保留系统下载安全检查") }
        _ = try AppUpdateCommand.run("/usr/sbin/spctl", ["--assess", "--type", "execute", candidate.path], timeout: 180)
    }

    static func validateMetadata(_ candidate: URL, application: UpdateApplication, asset: AppUpdateAsset) throws {
        guard let updated = UpdateApplication.read(at: candidate), updated.bundleID == application.bundleID else {
            throw AppUpdateInstallError.rejected("更新包中的应用标识不匹配")
        }
        let version = asset.buildOnly ? updated.build : updated.version
        guard UpdateVersion.compare(version, asset.version) == .orderedSame,
              asset.buildOnly || asset.build.flatMap(UpdateVersion.components) == nil || UpdateVersion.compare(updated.build, asset.build!) == .orderedSame else {
            throw AppUpdateInstallError.rejected("更新包版本与检测结果不一致，请重新扫描")
        }
        let order = UpdateVersion.compare(updated.version, application.version)
        let newerBuild = order == .orderedSame && UpdateVersion.compare(updated.build, application.build) == .orderedDescending
        guard order == .orderedDescending || newerBuild ||
                (asset.buildOnly && UpdateVersion.compare(updated.build, application.build) == .orderedDescending) else {
            throw AppUpdateInstallError.rejected("更新包不是更新的版本")
        }
        guard let info = NSDictionary(contentsOf: candidate.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
              !executable.contains("/"), executable != ".", executable != ".." else {
            throw AppUpdateInstallError.rejected("更新应用缺少有效的主程序")
        }
        let currentOS = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(currentOS.majorVersion).\(currentOS.minorVersion).\(currentOS.patchVersion)"
        if let minimum = info["LSMinimumSystemVersion"] as? String,
           UpdateVersion.compare(minimum, osVersion) == .orderedDescending {
            throw AppUpdateInstallError.rejected("更新应用不支持当前 macOS")
        }
        let binary = candidate.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        let architectures = String(decoding: try AppUpdateCommand.run("/usr/bin/lipo", ["-archs", binary.path]), as: UTF8.self)
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        guard architectures.split(whereSeparator: { $0.isWhitespace }).contains(Substring(architecture)) else {
            throw AppUpdateInstallError.rejected("更新应用不支持当前处理器架构")
        }
        if let enumerator = FileManager.default.enumerator(at: candidate, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            let boundary = candidate.resolvingSymlinksInPath().path + "/"
            for case let url as URL in enumerator {
                if (try url.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true,
                   !url.resolvingSymlinksInPath().path.hasPrefix(boundary) {
                    throw AppUpdateInstallError.rejected("更新应用包含指向应用外部的链接")
                }
            }
        }
    }

    static func verifyArchive(_ archive: URL, asset: AppUpdateAsset) throws {
        let size = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? Int64 ?? 0
        guard size > 0, size <= AppUpdateDownload.maximumSize else { throw AppUpdateInstallError.rejected("更新包为空或超过大小限制") }
        if let expected = asset.sha256 {
            guard expected.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else {
                throw AppUpdateInstallError.rejected("更新源未提供有效的 SHA-256 校验值")
            }
            let handle = try FileHandle(forReadingFrom: archive)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                hash.update(data: chunk)
            }
            let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard actual == expected.lowercased() else { throw AppUpdateInstallError.rejected("更新包 SHA-256 校验失败") }
        }
        if let publicKey = asset.publicEDKey {
            guard let key = Data(base64Encoded: publicKey), let signature = asset.edSignature.flatMap({ Data(base64Encoded: $0) }),
                  let signingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
                  signingKey.isValidSignature(signature, for: try Data(contentsOf: archive, options: .mappedIfSafe)) else {
                throw AppUpdateInstallError.rejected("更新包 Ed25519 签名校验失败")
            }
        }
    }

    private static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess else { return nil }
        return code
    }
}

enum AppUpdateCommand {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 120) throws -> Data {
        let process = Process()
        let pipe = Pipe()
        let ended = DispatchSemaphore(value: 0)
        let drained = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = pipe
        process.terminationHandler = { _ in ended.signal() }
        try process.run()
        let output = AppUpdateCommandOutput()
        DispatchQueue.global(qos: .utility).async {
            while let data = try? pipe.fileHandleForReading.read(upToCount: 64 * 1024), !data.isEmpty {
                output.append(data)
            }
            drained.signal()
        }
        if ended.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if ended.wait(timeout: .now() + 2) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = ended.wait(timeout: .now() + 2)
            }
            throw AppUpdateInstallError.rejected("更新工具执行超时：\(URL(fileURLWithPath: executable).lastPathComponent)")
        }
        _ = drained.wait(timeout: .now() + 5)
        guard process.terminationStatus == 0, !output.exceeded else {
            let message = String(decoding: output.data.prefix(1500), as: UTF8.self)
            throw AppUpdateInstallError.rejected("更新工具失败：\(URL(fileURLWithPath: executable).lastPathComponent)。\(message)")
        }
        return output.data
    }
}

private final class AppUpdateCommandOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var overflow = false
    var data: Data { lock.lock(); defer { lock.unlock() }; return bytes }
    var exceeded: Bool { lock.lock(); defer { lock.unlock() }; return overflow }
    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        if bytes.count + data.count <= 2 * 1024 * 1024 { bytes.append(data) } else { overflow = true }
    }
}

private final class AppUpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let maximumSize: Int64 = 8 * 1024 * 1024 * 1024
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL?
    private var progress: (@Sendable (Double) -> Void)?
    private var failure: Error?
    private var cancelled = false
    private var lastProgressTime: TimeInterval = 0

    func start(url: URL, destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard AppUpdateLookup.safeURL(url) != nil else { throw AppUpdateInstallError.rejected("下载地址不是有效的 HTTPS 地址") }
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if cancelled { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                self.destination = destination
                self.progress = progress
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 1800
                configuration.urlCredentialStorage = nil
                configuration.httpShouldSetCookies = false
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                self.session = session
                let task = session.downloadTask(with: url)
                self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: {
            self.lock.lock()
            self.cancelled = true
            let task = self.task
            self.lock.unlock()
            task?.cancel()
        })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap(AppUpdateLookup.safeURL) == nil ? nil : request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > Self.maximumSize || totalBytesExpectedToWrite > Self.maximumSize {
            failure = AppUpdateInstallError.rejected("更新包超过 8GB 大小限制")
            downloadTask.cancel()
        } else if totalBytesExpectedToWrite > 0 {
            let now = Date.timeIntervalSinceReferenceDate
            if now - lastProgressTime >= 0.15 || totalBytesWritten == totalBytesExpectedToWrite {
                lastProgressTime = now
                progress?(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                  response.url.flatMap(AppUpdateLookup.safeURL) != nil, let destination = destination else {
                throw AppUpdateInstallError.rejected("更新下载失败，请使用官方更新入口")
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch { failure = error }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let wasCancelled = cancelled
        lock.unlock()
        if wasCancelled { continuation?.resume(throwing: CancellationError()) }
        else if let error = failure ?? error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
        session.finishTasksAndInvalidate()
        self.session = nil
    }
}
