import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct UpdateApplication: Sendable {
    let name: String
    let path: URL
    let bundleID: String
    let version: String
    let build: String
    let isAppStore: Bool
    let feedURL: URL?
    var publicEDKey: String? = nil
    var requiresSignedFeed = false
    var isHomebrewManaged = false

    static func read(at url: URL) -> UpdateApplication? {
        guard url.pathExtension == "app",
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        var app = UpdateApplication(
            name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent,
            path: url, bundleID: info["CFBundleIdentifier"] as? String ?? "",
            version: info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            isAppStore: FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path),
            feedURL: (info["SUFeedURL"] as? String).flatMap(URL.init(string:)))
        app.publicEDKey = info["SUPublicEDKey"] as? String
        app.requiresSignedFeed = info["SURequireSignedFeed"] as? Bool ?? false
        if let token = AppUpdateLookup.caskTokens[app.bundleID.lowercased()] {
            app.isHomebrewManaged = ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"].contains {
                FileManager.default.fileExists(atPath: $0 + "/" + token)
            }
        }
        return app
    }

    static func installed(in roots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ]) -> [UpdateApplication] {
        var seen = Set<String>()
        return roots.flatMap { root -> [UpdateApplication] in
            let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return files.compactMap { url in
                guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { return nil }
                return read(at: url)
            }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum UpdateCheckState: String, CaseIterable, Sendable {
    case available, current, unsupported, failed
}

struct AppUpdateAsset: Sendable {
    enum Format: String, Sendable { case dmg, zip, archive }
    let url: URL
    let format: Format
    let version: String
    let build: String?
    let buildOnly: Bool
    var sha256: String?
    var edSignature: String?
    var publicEDKey: String?

    init?(url: URL, version: String, build: String? = nil, buildOnly: Bool = false,
          sha256: String? = nil, edSignature: String? = nil, publicEDKey: String? = nil,
          allowOpaqueURL: Bool = false) {
        guard AppUpdateLookup.safeURL(url) != nil else { return nil }
        let suffix = url.pathExtension.lowercased()
        let format: Format
        if suffix == "dmg" { format = .dmg }
        else if suffix == "zip" { format = .zip }
        else if ["tar", "gz", "bz2", "xz", "tgz"].contains(suffix) || (allowOpaqueURL && suffix != "pkg") { format = .archive }
        else { return nil }
        self.url = url
        self.format = format
        self.version = version
        self.build = build
        self.buildOnly = buildOnly
        self.sha256 = sha256
        self.edSignature = edSignature
        self.publicEDKey = publicEDKey
    }
}

struct UpdateCheck: Sendable {
    let state: UpdateCheckState
    let source: String
    var version: String = ""
    var message: String = ""
    var url: URL? = nil
    var storeID: Int? = nil
    var notes: String = ""
    var asset: AppUpdateAsset? = nil
}

enum UpdateLookupError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

enum UpdateVersion {
    static func components(_ value: String) -> [Int]? {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("Build ") { value.removeFirst(6) }
        if value.hasPrefix("v") { value.removeFirst() }
        guard value.range(of: #"^[0-9]+(?:[._][0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(whereSeparator: { $0 == "." || $0 == "_" }).compactMap { Int($0) }
        guard parts.count == value.split(whereSeparator: { $0 == "." || $0 == "_" }).count else { return nil }
        return parts
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let a = components(lhs), let b = components(rhs) else { return nil }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }

    static func result(app: UpdateApplication, version: String, build: String? = nil,
                       source: String, url: URL?, notes: String = "", storeID: Int? = nil) -> UpdateCheck {
        guard let comparison = compare(version, app.version) else {
            return UpdateCheck(state: .unsupported, source: source, version: version,
                               message: "版本格式或发布通道不同，需在应用内确认", url: url)
        }
        let newerBuild = comparison == .orderedSame && build.flatMap { compare($0, app.build) } == .orderedDescending
        return UpdateCheck(state: comparison == .orderedDescending || newerBuild ? .available : .current,
                           source: source, version: newerBuild ? "\(version) (\(build!))" : version,
                           url: url, storeID: storeID, notes: notes)
    }
}

final class AppUpdateLookup: @unchecked Sendable {
    typealias Fetch = @Sendable (URL) async throws -> Data
    private let fetch: Fetch
    private let osVersion: String

    init(osVersion: String? = nil, fetch: Fetch? = nil) {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        self.osVersion = osVersion ?? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        if let fetch = fetch {
            self.fetch = fetch
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 18
            configuration.httpMaximumConnectionsPerHost = 4
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration)
            self.fetch = { url in
                guard Self.safeURL(url) != nil else { throw UpdateLookupError.invalid("更新源不是有效的 HTTPS 地址") }
                let (data, response) = try await session.data(from: url)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode),
                      response.url.flatMap(Self.safeURL) != nil else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    throw UpdateLookupError.invalid("更新源请求失败（HTTP \(code)）")
                }
                guard data.count <= 8 * 1024 * 1024 else { throw UpdateLookupError.invalid("更新元数据过大") }
                return data
            }
        }
    }

    static func safeURL(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    func check(_ app: UpdateApplication) async -> UpdateCheck {
        guard !app.bundleID.isEmpty else { return UpdateCheck(state: .unsupported, source: "—", message: "缺少应用标识") }
        if app.isAppStore {
            do { return try await appStore(app) }
            catch { return failure("App Store", error) }
        }
        var errors: [String] = []
        if app.bundleID.lowercased() == "com.tencent.xinwechat" {
            do { return try await weChat(app) }
            catch { errors.append("微信官网：\(error.localizedDescription)") }
        }
        if let feed = app.feedURL {
            if Self.safeURL(feed) == nil {
                errors.append("Sparkle：更新源不是 HTTPS 地址")
            } else {
                do { return try sparkle(app, data: await fetch(feed)) }
                catch { errors.append("Sparkle：\(error.localizedDescription)") }
            }
        }
        if let token = Self.caskTokens[app.bundleID.lowercased()] {
            do {
                let data = try await fetch(URL(string: "https://formulae.brew.sh/api/cask/\(token).json")!)
                var result = try cask(app, token: token, data: data)
                if !errors.isEmpty { result.message = "已使用备用更新源；" + errors.joined(separator: "；") }
                return result
            } catch { errors.append("Homebrew：\(error.localizedDescription)") }
        }
        if !errors.isEmpty { return UpdateCheck(state: .failed, source: "更新源", message: errors.joined(separator: "；")) }
        return UpdateCheck(state: .unsupported, source: "—", message: "尚未接入此应用的更新源，请使用应用内更新")
    }

    private func failure(_ source: String, _ error: Error) -> UpdateCheck {
        UpdateCheck(state: .failed, source: source, message: error.localizedDescription)
    }

    private func appStore(_ app: UpdateApplication) async throws -> UpdateCheck {
        var errors: [String] = []
        for country in ["cn", "us"] {
            var parts = URLComponents(string: "https://itunes.apple.com/lookup")!
            parts.queryItems = [URLQueryItem(name: "bundleId", value: app.bundleID),
                               URLQueryItem(name: "entity", value: "macSoftware"), URLQueryItem(name: "country", value: country)]
            do {
                let data = try await fetch(parts.url!)
                let response = try JSONDecoder().decode(StoreResponse.self, from: data)
                guard let item = response.results.first(where: { $0.bundleId.caseInsensitiveCompare(app.bundleID) == .orderedSame }) else { continue }
                let url = URL(string: "https://apps.apple.com/\(country)/app/id\(item.trackId)")!
                if let minimum = item.minimumOsVersion, UpdateVersion.compare(minimum, osVersion) == .orderedDescending {
                    return UpdateCheck(state: .unsupported, source: "App Store", version: item.version,
                                       message: "新版本需要 macOS \(minimum)", url: url)
                }
                return UpdateVersion.result(app: app, version: item.version, source: "App Store", url: url,
                                            notes: item.releaseNotes ?? "", storeID: item.trackId)
            } catch { errors.append("\(country)：\(error.localizedDescription)") }
        }
        if !errors.isEmpty { throw UpdateLookupError.invalid(errors.joined(separator: "；")) }
        return UpdateCheck(state: .unsupported, source: "App Store", message: "中国区及美国区未找到此应用，需在 App Store 确认")
    }

    private func weChat(_ app: UpdateApplication) async throws -> UpdateCheck {
        let url = URL(string: "https://mac.weixin.qq.com/")!
        let html = String(decoding: try await fetch(url), as: UTF8.self)
        let regex = try NSRegularExpression(pattern: #"https://dldir1v6\.qq\.com/weixin/Universal/Mac/WeChatMac_([0-9.]+)\.dmg"#)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { throw UpdateLookupError.invalid("微信官网版本信息解析失败") }
        var result = UpdateVersion.result(app: app, version: String(html[range]), source: "微信官网", url: url)
        if let downloadRange = Range(match.range, in: html), let download = URL(string: String(html[downloadRange])) {
            result.asset = AppUpdateAsset(url: download, version: String(html[range]))
        }
        return result
    }

    func cask(_ app: UpdateApplication, token: String, data: Data) throws -> UpdateCheck {
        var item = try JSONDecoder().decode(CaskResponse.self, from: data)
        guard item.token == token else { throw UpdateLookupError.invalid("Homebrew 应用标识不匹配") }
        // The API's default is ARM macOS; select the current OS/CPU variation when supplied.
        let major = Int(osVersion.split(separator: ".").first ?? "") ?? 0
        let names = [27: "golden_gate", 26: "tahoe", 15: "sequoia", 14: "sonoma", 13: "ventura", 12: "monterey"]
        #if arch(arm64)
        let key = names[major].map { "arm64_" + $0 }
        #else
        let key = names[major]
        #endif
        if let key = key, let variant = item.variations?[key] {
            item.version = variant.version ?? item.version
            item.depends_on = variant.depends_on ?? item.depends_on
            item.url = variant.url ?? item.url
            item.sha256 = variant.sha256 ?? item.sha256
            item.artifacts = variant.artifacts ?? item.artifacts
        }
        guard let url = URL(string: item.homepage).flatMap(Self.safeURL) else { throw UpdateLookupError.invalid("官网更新入口无效") }
        guard item.disabled != true else { return UpdateCheck(state: .unsupported, source: "Homebrew", message: "此应用已从 Homebrew 停用", url: url) }
        if let minimum = item.depends_on?.macos?[">="]?.first, UpdateVersion.compare(minimum, osVersion) == .orderedDescending {
            return UpdateCheck(state: .unsupported, source: "Homebrew", version: item.version, message: "新版本需要 macOS \(minimum)", url: url)
        }
        let versions = item.version.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let build = versions.count == 2 ? versions[1] : nil
        var result = UpdateVersion.result(app: app, version: versions.first ?? "", build: build, source: "Homebrew / \(token)", url: url)
        let artifacts = item.artifacts ?? []
        if artifacts.filter({ $0.appName != nil }).count == 1, !artifacts.contains(where: { $0.requiresInstaller }),
           let download = item.url.flatMap(URL.init(string:)) {
            result.asset = AppUpdateAsset(url: download, version: versions.first ?? "", build: build,
                                         sha256: item.sha256 == "no_check" ? nil : item.sha256, allowOpaqueURL: true)
        }
        return result
    }

    func sparkle(_ app: UpdateApplication, data: Data) throws -> UpdateCheck {
        let items = try SparkleAppcast.read(data)
        let stable = items.filter { $0.channel.isEmpty && $0.os == "macos" && $0.isFullUpdate }
        guard !stable.isEmpty else { throw UpdateLookupError.invalid("更新源没有可识别的稳定版 macOS 更新") }
        let compatible = stable.filter { item in
            (item.minimumOS.isEmpty || UpdateVersion.compare(item.minimumOS, osVersion) != .orderedDescending) &&
            (item.maximumOS.isEmpty || UpdateVersion.compare(item.maximumOS, osVersion) != .orderedAscending)
        }
        guard !compatible.isEmpty else { return UpdateCheck(state: .unsupported, source: "Sparkle", message: "更新源中的版本不支持当前 macOS") }
        let candidates = compatible.filter { UpdateVersion.components($0.displayVersion) != nil }
        guard let newest = candidates.max(by: { lhs, rhs in
            let order = UpdateVersion.compare(lhs.displayVersion, rhs.displayVersion)
            return order == .orderedAscending || (order == .orderedSame && UpdateVersion.compare(lhs.build, rhs.build) == .orderedAscending)
        }) else { throw UpdateLookupError.invalid("更新源版本格式无法识别") }
        let url = newest.link.flatMap(URL.init(string:)).flatMap(Self.safeURL)
        guard url != nil else { throw UpdateLookupError.invalid("更新源缺少安全的更新入口") }
        if newest.shortVersion.isEmpty {
            guard let order = UpdateVersion.compare(newest.build, app.build) else {
                return UpdateCheck(state: .unsupported, source: "Sparkle", message: "无法比较应用构建号", url: url)
            }
            var result = UpdateCheck(state: order == .orderedDescending ? .available : .current, source: "Sparkle",
                                     version: newest.build, url: url)
            result.asset = sparkleAsset(app, item: newest, buildOnly: true)
            return result
        }
        var result = UpdateVersion.result(app: app, version: newest.shortVersion, build: newest.build, source: "Sparkle", url: url)
        result.asset = sparkleAsset(app, item: newest)
        return result
    }

    private func sparkleAsset(_ app: UpdateApplication, item: SparkleItem, buildOnly: Bool = false) -> AppUpdateAsset? {
        guard !app.requiresSignedFeed, item.installationType != "package", item.installationType != "guided-package",
              let download = item.download.flatMap(URL.init(string:)) else { return nil }
        if !item.minimumAutoupdate.isEmpty {
            guard let order = UpdateVersion.compare(app.build, item.minimumAutoupdate), order != .orderedAscending else { return nil }
        }
        return AppUpdateAsset(url: download, version: item.displayVersion, build: item.build, buildOnly: buildOnly,
                              edSignature: item.edSignature, publicEDKey: app.publicEDKey, allowOpaqueURL: true)
    }

    // Exact bundle IDs avoid matching similarly named, beta, regional, or store editions.
    static let caskTokens: [String: String] = [
        "com.runningwithcrayons.alfred": "alfred", "com.google.chrome": "google-chrome",
        "com.docker.docker": "docker-desktop", "md.obsidian": "obsidian",
        "com.postmanlabs.mac": "postman", "com.googlecode.iterm2": "iterm2",
        "abnerworks.typora": "typora", "com.jetbrains.goland": "goland",
        "com.github.marktext.marktext": "mark-text", "org.gnome.meld": "meld",
        "com.microsoft.word": "microsoft-word", "com.microsoft.excel": "microsoft-excel",
        "com.microsoft.powerpoint": "microsoft-powerpoint", "com.microsoft.outlook": "microsoft-outlook",
        "com.microsoft.onenote.mac": "microsoft-onenote", "com.microsoft.onedrive": "onedrive",
        "com.alienator88.pearcleaner": "pearcleaner", "com.sublimetext.4": "sublime-text",
        "switchhosts": "switchhosts", "com.macpaw.site.theunarchiver": "the-unarchiver",
        "com.netease.163music": "neteasemusic", "com.tencent.qqmusicmac": "qqmusic",
        "com.baidu.baidunetdisk-mac": "baidunetdisk", "com.xunlei.thunder": "thunder",
        "com.ticktick.task.mac": "ticktick", "org.wireshark.wireshark": "wireshark",
        "com.tencent.xinwechat": "wechat", "com.yinxiang.mac": "yinxiangbiji",
        "com.aionui.app": "aionui", "com.bot.pc.doubao": "doubao"
    ]
}

private struct StoreResponse: Decodable {
    var results: [StoreItem]
}
private struct StoreItem: Decodable {
    var bundleId: String
    var version: String
    var trackId: Int
    var releaseNotes: String?
    var minimumOsVersion: String?
}
private struct CaskResponse: Decodable {
    var token: String
    var version: String
    var homepage: String
    var disabled: Bool?
    var depends_on: CaskDependencies?
    var variations: [String: CaskVariation]?
    var url: String?
    var sha256: String?
    var artifacts: [CaskArtifact]?
}
private struct CaskDependencies: Decodable {
    var macos: [String: [String]]?
}
private struct CaskVariation: Decodable {
    var version: String?
    var depends_on: CaskDependencies?
    var url: String?
    var sha256: String?
    var artifacts: [CaskArtifact]?
}
private struct CaskArtifact: Decodable {
    var appName: String?
    var requiresInstaller: Bool
    enum CodingKeys: String, CodingKey { case app, pkg, installer }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        if values.contains(.app), var apps = try? values.nestedUnkeyedContainer(forKey: .app) {
            appName = try? apps.decode(String.self)
        }
        requiresInstaller = values.contains(.pkg) || values.contains(.installer)
    }
}

struct SparkleItem {
    var shortVersion = ""
    var build = ""
    var minimumOS = ""
    var maximumOS = ""
    var channel = ""
    var os = "macos"
    var isFullUpdate = false
    var link: String?
    var download: String?
    var edSignature: String?
    var installationType = ""
    var minimumAutoupdate = ""
    var displayVersion: String { shortVersion.isEmpty ? build : shortVersion }
}

private final class SparkleAppcast: NSObject, XMLParserDelegate {
    private var items: [SparkleItem] = []
    private var item: SparkleItem?
    private var stack: [String] = []
    private var text = ""

    static func read(_ data: Data) throws -> [SparkleItem] {
        let delegate = SparkleAppcast()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw UpdateLookupError.invalid("Sparkle XML 解析失败") }
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(element)
        text = ""
        if element == "item" { item = SparkleItem() }
        guard element == "enclosure", stack.count >= 2, stack[stack.count - 2] == "item",
              attributes["sparkle:deltaFrom"] == nil, var value = item else { return }
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let architectures = (attributes["sparkle:arch"] ?? "").split { $0 == "," || $0.isWhitespace }.map(String.init)
        guard architectures.isEmpty || architectures.contains(architecture),
              attributes["sparkle:os"] == nil || attributes["sparkle:os"] == "macos" else { return }
        value.isFullUpdate = true
        value.shortVersion = attributes["sparkle:shortVersionString"] ?? value.shortVersion
        value.build = attributes["sparkle:version"] ?? value.build
        value.os = attributes["sparkle:os"] ?? "macos"
        value.link = attributes["url"]
        value.download = attributes["url"]
        value.edSignature = attributes["sparkle:edSignature"]
        value.installationType = attributes["sparkle:installationType"] ?? ""
        item = value
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        defer { if !stack.isEmpty { stack.removeLast() }; text = "" }
        guard var value = item else { return }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stack.count >= 2, stack[stack.count - 2] == "item" {
            switch element {
            case "sparkle:shortVersionString": value.shortVersion = content
            case "sparkle:version": value.build = content
            case "sparkle:minimumSystemVersion": value.minimumOS = content
            case "sparkle:maximumSystemVersion": value.maximumOS = content
            case "sparkle:channel": value.channel = content
            case "sparkle:minimumAutoupdateVersion": value.minimumAutoupdate = content
            case "link": if !content.isEmpty { value.link = content }
            default: break
            }
        }
        if element == "item" { items.append(value); item = nil } else { item = value }
    }
}
