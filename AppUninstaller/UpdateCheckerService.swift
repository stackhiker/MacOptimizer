import Foundation
import Combine

/// Checks published releases only. Downloads remain an explicit browser action.
final class UpdateCheckerService: ObservableObject {
    static let shared = UpdateCheckerService()
    enum CheckState: Equatable { case notChecked, checking, updateAvailable, upToDate, unverifiable, noPublishedRelease, failed, cancelled }
    enum CheckSource { case api, publicReleasePage }
    @Published private(set) var hasUpdate = false
    @Published private(set) var latestVersion = ""
    @Published private(set) var releaseNotes = ""
    @Published private(set) var downloadURL: URL?
    @Published private(set) var isChecking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var state: CheckState = .notChecked
    @Published private(set) var checkedAt: Date?
    @Published private(set) var lastAttemptAt: Date?
    @Published private(set) var apiRetryAt: Date?
    @Published private(set) var lastCheckSource: CheckSource?

    let currentVersion: String
    let currentBuild: String
    let repository: String
    private let load: (URLRequest) async throws -> (Data, URLResponse)
    private let now: () -> Date
    private let backoffDefaults: UserDefaults?
    private var backoffKey: String { "MacOptimizer.UpdateAPIRetryAt." + repository.lowercased() }
    private var session: URLSession?
    @MainActor private var checkTask: Task<Void, Never>?
    @MainActor private var activeCheckID: UUID?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
         load: ((URLRequest) async throws -> (Data, URLResponse))? = nil,
         now: @escaping () -> Date = Date.init,
         defaults: UserDefaults? = nil) {
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "5.0"
        currentBuild = info["CFBundleVersion"] as? String ?? "—"
        repository = info["UpdateRepository"] as? String ?? "stackhiker/MacOptimizer"
        self.now = now
        // Injected transports never read or write the user's preferences by default.
        backoffDefaults = defaults ?? (load == nil ? .standard : nil)
        if let load { self.load = load } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 12
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            self.session = session
            self.load = { try await session.data(for: $0) }
        }
        if let value = backoffDefaults?.object(forKey: backoffKey) as? Double {
            let date = Date(timeIntervalSince1970: value)
            if date > now() { apiRetryAt = date }
            else { backoffDefaults?.removeObject(forKey: backoffKey) }
        }
    }
    deinit { session?.invalidateAndCancel() }

    var currentVersionDisplay: String { "\(currentVersion) (Build \(currentBuild))" }
    var statusText: String {
        let loc = LocalizationManager.shared
        switch state {
        case .notChecked: return loc.text("尚未检查更新", "Updates have not been checked")
        case .checking: return loc.text("正在检查更新…", "Checking for updates…")
        case .updateAvailable: return loc.text("发现更新：", "Update available: ") + latestVersion
        case .upToDate: return loc.text("当前版本不低于此更新渠道的最新版本", "This version is current or newer than this release channel")
        case .unverifiable: return loc.text("发布信息缺少构建号，无法确认同版本是否有更新", "Release metadata lacks a build number; same-version updates cannot be determined")
        case .noPublishedRelease: return loc.text("此更新渠道尚未发布正式版本", "This channel has no published release yet")
        case .failed: return loc.text("更新检查失败", "Update check failed")
        case .cancelled: return loc.text("更新检查已停止", "Update check stopped")
        }
    }

    var sourceText: String? {
        guard let lastCheckSource else { return nil }
        let loc = LocalizationManager.shared
        switch lastCheckSource {
        case .api: return loc.text("已通过 GitHub 发布接口检查", "Checked using the GitHub release API")
        case .publicReleasePage: return loc.text("已通过 GitHub 公开发行页检查", "Checked using the public GitHub releases page")
        }
    }

    @MainActor func checkForUpdates() async {
        if let checkTask { await checkTask.value; return }
        let id = UUID()
        activeCheckID = id
        isChecking = true
        state = .checking
        errorMessage = nil
        hasUpdate = false
        downloadURL = nil
        lastCheckSource = nil
        lastAttemptAt = now()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCheck(id: id)
            guard self.activeCheckID == id else { return }
            self.isChecking = false
            self.activeCheckID = nil
            self.checkTask = nil
        }
        checkTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    @MainActor func cancelCheck() { checkTask?.cancel() }

    @MainActor private func performCheck(id: UUID) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 12
        do {
            try Task.checkCancellation()
            guard Self.validRepository(repository),
                  let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
                throw UpdateCheckError.invalidRepository
            }
            if let retry = apiRetryAt, retry > now() {
                try await checkPublicReleasePage(id: id, deadline: deadline)
                return
            }
            setAPIRetry(nil)
            let (data, response) = try await request(url, accept: "application/vnd.github+json", deadline: deadline)
            try Task.checkCancellation()
            guard activeCheckID == id else { return }
            guard let http = response as? HTTPURLResponse,
                  Self.isTrustedURL(http.url, host: "api.github.com"),
                  http.url?.path.lowercased() == "/repos/\(repository.lowercased())/releases/latest" else {
                throw UpdateCheckError.invalidResponse
            }
            if let retry = Self.rateLimitRetryDate(response: http, data: data, now: now()) {
                setAPIRetry(retry)
                try await checkPublicReleasePage(id: id, deadline: deadline)
                return
            }
            if http.statusCode == 404 {
                // A missing API release is not proof that a private/inaccessible
                // repository has no releases. Verify the public repository page.
                try await checkPublicReleasePage(id: id, deadline: deadline)
                return
            }
            guard http.statusCode == 200 else { throw UpdateCheckError.http(http.statusCode) }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !release.draft, !release.prerelease,
                  let remote = ReleaseVersion.parse(release: release),
                  let releaseURL = URL(string: release.html_url),
                  Self.isTrustedReleaseURL(releaseURL, repository: repository) else {
                throw UpdateCheckError.invalidRelease
            }
            try publish(remote: remote, releaseURL: releaseURL, notes: release.body, source: .api)
        } catch {
            guard activeCheckID == id else { return }
            hasUpdate = false
            downloadURL = nil
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                state = .cancelled
                errorMessage = nil
            } else {
                state = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    private func request(_ url: URL, accept: String, deadline: TimeInterval) async throws -> (Data, URLResponse) {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw URLError(.timedOut) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = min(5, remaining)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("MacOptimizer/\(currentVersion) (Build \(currentBuild))", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask { [load] in try await load(request) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(min(remaining, 12) * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.badServerResponse) }
            return first
        }
    }

    @MainActor private func checkPublicReleasePage(id: UUID, deadline: TimeInterval) async throws {
        guard let url = URL(string: "https://github.com/\(repository)/releases/latest") else {
            throw UpdateCheckError.invalidRepository
        }
        let (data, response) = try await request(url, accept: "text/html", deadline: deadline)
        try Task.checkCancellation()
        guard activeCheckID == id else { return }
        guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
        guard http.statusCode == 200 else { throw UpdateCheckError.http(http.statusCode) }
        guard let finalURL = http.url,
              Self.isTrustedURL(finalURL, host: "github.com"),
              Self.isGitHubReleasePage(data, response: http, repository: repository) else {
            throw UpdateCheckError.invalidPublicReleasePage
        }
        let path = finalURL.path
        let releasesPath = "/\(repository)/releases"
        if path.lowercased() == releasesPath.lowercased() || path.lowercased() == releasesPath.lowercased() + "/" {
            guard let html = String(data: data, encoding: .utf8),
                  html.contains("There aren’t any releases here") || html.contains("There aren't any releases here") || html.contains("There aren&#39;t any releases here") else {
                throw UpdateCheckError.invalidPublicReleasePage
            }
            latestVersion = ""
            releaseNotes = ""
            downloadURL = nil
            hasUpdate = false
            checkedAt = now()
            lastCheckSource = .publicReleasePage
            state = .noPublishedRelease
            return
        }
        guard Self.isTrustedReleaseURL(finalURL, repository: repository),
              let tag = URLComponents(url: finalURL, resolvingAgainstBaseURL: false)?.percentEncodedPath.split(separator: "/").last.flatMap({ String($0).removingPercentEncoding }),
              let remote = ReleaseVersion.parsePublicTag(tag) else { throw UpdateCheckError.invalidPublicReleasePage }
        try publish(remote: remote, releaseURL: finalURL, notes: "", source: .publicReleasePage)
    }

    @MainActor private func publish(remote: ReleaseVersion, releaseURL: URL, notes: String, source: CheckSource) throws {
        guard let local = ReleaseVersion(version: currentVersion, build: Int(currentBuild)) else { throw UpdateCheckError.invalidRelease }
        latestVersion = remote.display
        releaseNotes = notes
        downloadURL = releaseURL
        checkedAt = now()
        lastCheckSource = source
        switch remote.compare(to: local) {
        case .newer: hasUpdate = true; state = .updateAvailable
        case .sameOrOlder: hasUpdate = false; state = .upToDate
        case .unknown: hasUpdate = false; state = .unverifiable
        }
    }

    private func setAPIRetry(_ date: Date?) {
        apiRetryAt = date
        if let date { backoffDefaults?.set(date.timeIntervalSince1970, forKey: backoffKey) }
        else { backoffDefaults?.removeObject(forKey: backoffKey) }
    }

    static func rateLimitRetryDate(response: HTTPURLResponse, data: Data, now: Date) -> Date? {
        let status = response.statusCode
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? ""
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
        let exhausted = response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
        guard status == 429 || (status == 403 && (exhausted || retryAfter != nil || message.lowercased().contains("rate limit"))) else { return nil }
        if let retryAfter {
            if let seconds = TimeInterval(retryAfter.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds > 0 {
                return now.addingTimeInterval(seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            if let date = formatter.date(from: retryAfter), date > now { return date }
        }
        if exhausted, let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init), reset.isFinite {
            let date = Date(timeIntervalSince1970: reset)
            if date > now { return date }
        }
        return now.addingTimeInterval(60)
    }

    static func isTrustedURL(_ url: URL?, host: String) -> Bool {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme?.lowercased() == "https" && components.host?.lowercased() == host
            && components.user == nil && components.password == nil && components.query == nil && components.fragment == nil
            && (components.port == nil || components.port == 443)
    }
    static func isTrustedReleaseURL(_ url: URL, repository: String) -> Bool {
        guard isTrustedURL(url, host: "github.com") else { return false }
        guard let encodedPath = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return false }
        let encodedParts = encodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard encodedParts.count == 6, encodedParts[0].isEmpty else { return false }
        let parts = encodedParts.dropFirst().compactMap { String($0).removingPercentEncoding }
        let repo = repository.split(separator: "/").map(String.init)
        return parts.count == 5 && repo.count == 2
            && !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." || $0.contains("/") || $0.contains("\\") || $0.contains("%") })
            && parts[0].lowercased() == repo[0].lowercased() && parts[1].lowercased() == repo[1].lowercased()
            && parts[2] == "releases" && parts[3] == "tag"
    }
    private static func isGitHubReleasePage(_ data: Data, response: HTTPURLResponse, repository: String) -> Bool {
        guard data.count > 0, data.count <= 2_000_000,
              response.mimeType?.lowercased() == "text/html", let html = String(data: data, encoding: .utf8),
              html.lowercased().contains("<html") else { return false }
        func meta(_ name: String, attribute: String = "name") -> String? {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let pattern = "<meta\\s+[^>]*" + attribute + "=[\"']" + escaped + "[\"'][^>]*content=[\"']([^\"']*)[\"'][^>]*>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
        return meta("og:site_name", attribute: "property") == "GitHub"
            && meta("octolytics-dimension-repository_nwo")?.lowercased() == repository.lowercased()
            && meta("route-controller") == "releases"
    }
    static func validRepository(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
            && !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }
}

private enum UpdateCheckError: LocalizedError {
    case invalidRepository, invalidResponse, http(Int), invalidRelease, invalidPublicReleasePage
    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "更新仓库配置无效 / Invalid update repository"
        case .invalidResponse: return "更新服务器响应无效 / Invalid update response"
        case .http(let status): return "更新服务器返回 HTTP \(status) / Release server returned HTTP \(status)"
        case .invalidRelease: return "发布版本信息或链接无效 / Invalid release version or URL"
        case .invalidPublicReleasePage: return "无法验证 GitHub 公开发行页 / Public GitHub release page could not be verified"
        }
    }
}

struct ReleaseVersion: Equatable {
    enum Comparison { case newer, sameOrOlder, unknown }
    let components: [Int]
    let version: String
    let build: Int?
    var display: String { build.map { "\(version) (Build \($0))" } ?? version }

    init?(version: String, build: Int?) {
        let value = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = value.range(of: #"^[vV]?[0-9]+(?:\.[0-9]+)*(?=$|[-+_])"#, options: .regularExpression) else { return nil }
        let number = String(value[range]).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = number.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.version = number
        self.components = parts
        self.build = build.flatMap { $0 >= 0 ? $0 : nil }
    }

    func compare(to local: ReleaseVersion) -> Comparison {
        for index in 0..<max(components.count, local.components.count) {
            let remotePart = index < components.count ? components[index] : 0
            let localPart = index < local.components.count ? local.components[index] : 0
            if remotePart > localPart { return .newer }
            if remotePart < localPart { return .sameOrOlder }
        }
        guard let build, let localBuild = local.build else { return .unknown }
        return build > localBuild ? .newer : .sameOrOlder
    }

    static func parse(release: GitHubRelease) -> ReleaseVersion? {
        let tagBuild = extractBuild(release.tag_name)
        let assetBuilds = Set(release.assets.compactMap { extractBuild($0.name) })
        let assetBuild = assetBuilds.count == 1 ? assetBuilds.first : nil
        let metadataBuild = release.build_number ?? release.metadata?.build
            ?? captureInteger(in: release.body, pattern: #"(?i)\bbuild(?:_number)?\s*[:=]\s*["']?(\d+)"#)
        return ReleaseVersion(version: release.tag_name, build: tagBuild ?? metadataBuild ?? assetBuild)
    }

    static func parsePublicTag(_ tag: String) -> ReleaseVersion? {
        guard tag.range(of: #"^[vV]?[0-9]+(?:\.[0-9]+)*(?:[-_+]build[-_ ]?[0-9]+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return ReleaseVersion(version: tag, build: extractBuild(tag))
    }

    private static func extractBuild(_ text: String) -> Int? {
        captureInteger(in: text, pattern: #"(?i)(?:^|[-_+ .])build[-_ ]?(\d+)(?=$|[._+ -])"#)
    }
    private static func captureInteger(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[range])
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable { let name: String }
    struct Metadata: Decodable { let build: Int? }
    let tag_name: String
    let html_url: String
    let body: String
    let assets: [Asset]
    let build_number: Int?
    let metadata: Metadata?
    let draft: Bool
    let prerelease: Bool
    private enum CodingKeys: String, CodingKey { case tag_name, html_url, body, assets, build_number, metadata, draft, prerelease }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tag_name = try c.decode(String.self, forKey: .tag_name)
        html_url = try c.decode(String.self, forKey: .html_url)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        assets = try c.decodeIfPresent([Asset].self, forKey: .assets) ?? []
        if let number = try? c.decode(Int.self, forKey: .build_number) { build_number = number }
        else { build_number = (try? c.decode(String.self, forKey: .build_number)).flatMap(Int.init) }
        metadata = try c.decodeIfPresent(Metadata.self, forKey: .metadata)
        draft = try c.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try c.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
    }
}
