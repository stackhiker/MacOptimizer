import Foundation
import Combine

/// Checks this product's release channel. Downloads remain an explicit browser action.
final class UpdateCheckerService: ObservableObject {
    static let shared = UpdateCheckerService()
    enum CheckState: Equatable { case notChecked, checking, updateAvailable, upToDate, unverifiable, failed, cancelled }
    @Published private(set) var hasUpdate = false
    @Published private(set) var latestVersion = ""
    @Published private(set) var releaseNotes = ""
    @Published private(set) var downloadURL: URL?
    @Published private(set) var isChecking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var state: CheckState = .notChecked
    @Published private(set) var checkedAt: Date?
    @Published private(set) var lastAttemptAt: Date?

    let currentVersion: String
    let currentBuild: String
    let repository: String
    private let load: (URLRequest) async throws -> (Data, URLResponse)
    private let now: () -> Date
    private var session: URLSession?
    @MainActor private var checkTask: Task<Void, Never>?
    @MainActor private var activeCheckID: UUID?

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:],
         load: ((URLRequest) async throws -> (Data, URLResponse))? = nil,
         now: @escaping () -> Date = Date.init) {
        currentVersion = info["CFBundleShortVersionString"] as? String ?? "5.0"
        currentBuild = info["CFBundleVersion"] as? String ?? "—"
        repository = info["UpdateRepository"] as? String ?? "stackhiker/MacOptimizer"
        self.now = now
        if let load { self.load = load } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 10
            configuration.waitsForConnectivity = false
            let session = URLSession(configuration: configuration)
            self.session = session
            self.load = { try await session.data(for: $0) }
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
        case .failed: return loc.text("更新检查失败", "Update check failed")
        case .cancelled: return loc.text("更新检查已停止", "Update check stopped")
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
        do {
            try Task.checkCancellation()
            guard Self.validRepository(repository), let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
                throw UpdateCheckError.invalidRepository
            }
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await load(request)
            try Task.checkCancellation()
            guard activeCheckID == id else { return }
            guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
            guard http.statusCode == 200 else { throw UpdateCheckError.http(http.statusCode) }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !release.draft, !release.prerelease,
                  let remote = ReleaseVersion.parse(release: release),
                  let local = ReleaseVersion(version: currentVersion, build: Int(currentBuild)) else {
                throw UpdateCheckError.invalidRelease
            }
            let comparison = remote.compare(to: local)
            latestVersion = remote.display
            releaseNotes = release.body
            if let releaseURL = URL(string: release.html_url), releaseURL.scheme == "https",
               releaseURL.host?.lowercased() == "github.com",
               releaseURL.path.hasPrefix("/\(repository)/releases/") {
                downloadURL = releaseURL
            } else { throw UpdateCheckError.invalidReleaseURL }
            checkedAt = now()
            switch comparison {
            case .newer: hasUpdate = true; state = .updateAvailable
            case .sameOrOlder: hasUpdate = false; state = .upToDate
            case .unknown: hasUpdate = false; state = .unverifiable
            }
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

    static func validRepository(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil
            && !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }
}

private enum UpdateCheckError: LocalizedError {
    case invalidRepository, invalidResponse, http(Int), invalidRelease, invalidReleaseURL
    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "更新仓库配置无效 / Invalid update repository"
        case .invalidResponse: return "更新服务器响应无效 / Invalid update response"
        case .http(let status): return "更新服务器返回 HTTP \(status) / Release server returned HTTP \(status)"
        case .invalidRelease: return "发布版本信息无效 / Invalid release version metadata"
        case .invalidReleaseURL: return "发布链接不属于配置的仓库 / Release URL does not belong to the configured repository"
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
