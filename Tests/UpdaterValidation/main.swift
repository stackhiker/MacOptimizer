import Foundation

@main
struct UpdaterValidation {
    static func app(version: String = "1.0", build: String = "10", id: String = "md.obsidian", store: Bool = false, feed: String? = nil) -> UpdateApplication {
        UpdateApplication(name: "Fixture", path: URL(fileURLWithPath: "/Applications/Fixture.app"), bundleID: id,
                          version: version, build: build, isAppStore: store, feedURL: feed.flatMap(URL.init(string:)))
    }

    static func main() async throws {
        if let index = CommandLine.arguments.firstIndex(of: "--verify-installed-copy"), index + 1 < CommandLine.arguments.count {
            let source = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            guard let installed = UpdateApplication.read(at: source) else { fatalError("Expected an existing signed app bundle") }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MacOptimizerSigningTest-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let candidate = directory.appendingPathComponent("SignedCopy.app")
            _ = try AppUpdateCommand.run("/usr/bin/ditto", [source.path, candidate.path], timeout: 600)
            let previous = UpdateApplication(name: installed.name, path: source, bundleID: installed.bundleID,
                                             version: "0", build: "0", isAppStore: false, feedURL: nil)
            let asset = AppUpdateAsset(url: URL(string: "https://example.invalid/signed.zip")!, version: installed.version, build: installed.build)!
            try AppUpdateVerifier.validate(candidate, application: previous, asset: asset, original: source)
            print("PASS: production signature, developer requirement, architecture and Gatekeeper checks on a temporary signed app copy")
            return
        }
        if CommandLine.arguments.contains("--live") {
            let lookup = AppUpdateLookup()
            let apps = UpdateApplication.installed()
            await withTaskGroup(of: (UpdateApplication, UpdateCheck).self) { group in
                var iterator = apps.makeIterator()
                for _ in 0..<6 { if let value = iterator.next() { group.addTask { (value, await lookup.check(value)) } } }
                while let (value, check) = await group.next() {
                    let row = ["app": value.name, "installed": value.version, "latest": check.version,
                               "state": check.state.rawValue, "source": check.source, "message": check.message,
                               "automatic": String(check.state == .available && AppUpdateInstaller.unavailableReason(for: value, check: check) == nil),
                               "manualReason": check.state == .available ? (AppUpdateInstaller.unavailableReason(for: value, check: check) ?? "") : ""]
                    let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                    print(String(decoding: data, as: UTF8.self))
                    if let value = iterator.next() { group.addTask { (value, await lookup.check(value)) } }
                }
            }
            return
        }
        var passed = 0
        func expect(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            passed += 1
            print("PASS: \(name)")
        }
        expect(UpdateVersion.compare("1.10", "1.9") == .orderedDescending, "numeric ordering")
        expect(UpdateVersion.compare("1.0.0", "1") == .orderedSame, "zero padding")
        expect(UpdateVersion.compare("Build 4215", "4214") == .orderedDescending, "Sublime build version")
        expect(UpdateVersion.compare("latest", "1") == nil, "unknown version is not current")
        expect(UpdateVersion.compare("2.0-beta", "1") == nil, "do not cross prerelease channels")
        expect(UpdateVersion.compare("v2.0", "1") == .orderedDescending, "version prefix")
        expect(UpdateVersion.result(app: app(), version: "1.0", build: "11", source: "Test", url: nil).state == .available, "same version newer build")
        expect(UpdateVersion.result(app: app(version: "2"), version: "1", build: "99", source: "Test", url: nil).state == .current, "never suggest downgrade")
        expect(AppUpdateLookup.safeURL(URL(string: "javascript:alert(1)")!) == nil, "reject executable URLs")
        expect(AppUpdateLookup.safeURL(URL(string: "https://user:password@example.org")!) == nil, "reject credentials in update URLs")

        let lookup = AppUpdateLookup(osVersion: "14.0", fetch: { _ in throw URLError(.notConnectedToInternet) })
        let cask = Data(#"{"token":"obsidian","version":"1.10,20","homepage":"https://obsidian.md","depends_on":{"macos":{">=":["12"]}},"variations":{}}"#.utf8)
        expect(try lookup.cask(app(), token: "obsidian", data: cask).state == .available, "Homebrew version metadata")
        do { _ = try lookup.cask(app(), token: "docker-desktop", data: cask); expect(false, "cask identity mismatch") }
        catch { expect(true, "cask identity mismatch") }
        let newerOS = Data(#"{"token":"obsidian","version":"2.0","homepage":"https://obsidian.md","depends_on":{"macos":{">=":["15"]}}}"#.utf8)
        expect(try lookup.cask(app(), token: "obsidian", data: newerOS).state == .unsupported, "minimum OS compatibility")
        let caskLatest = Data(#"{"token":"obsidian","version":"latest","homepage":"https://obsidian.md"}"#.utf8)
        expect(try lookup.cask(app(), token: "obsidian", data: caskLatest).state == .unsupported, "Homebrew latest sentinel")
        let disabled = Data(#"{"token":"obsidian","version":"2","homepage":"https://obsidian.md","disabled":true}"#.utf8)
        expect(try lookup.cask(app(), token: "obsidian", data: disabled).state == .unsupported, "disabled casks")

        let xml = Data("""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>20</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
        <sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion><enclosure url="https://example.org/app.zip"/>
        <sparkle:deltas><enclosure url="https://example.org/delta.zip" sparkle:version="99" sparkle:deltaFrom="1"/></sparkle:deltas></item>
        <item><sparkle:channel>beta</sparkle:channel><enclosure sparkle:version="90" sparkle:shortVersionString="9.0" url="https://example.org/beta.zip"/></item>
        <item><sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion><enclosure sparkle:version="100" sparkle:shortVersionString="10.0" url="https://example.org/new.zip"/></item>
        </channel></rss>
        """.utf8)
        let sparkle = try lookup.sparkle(app(), data: xml)
        expect(sparkle.state == .available && sparkle.version == "2.0", "Sparkle excludes beta and incompatible OS")
        expect(sparkle.url?.lastPathComponent == "app.zip", "Sparkle excludes delta packages")
        let oldXML = Data(#"<rss><channel><item><enclosure sparkle:version="20" sparkle:shortVersionString="2.0" url="https://example.org/app.zip"/></item></channel></rss>"#.utf8)
        expect(try lookup.sparkle(app(), data: oldXML).state == .available, "legacy Sparkle enclosure attributes")
        let buildXML = Data(#"<rss><channel><item><enclosure sparkle:version="11" url="https://example.org/app.zip"/></item></channel></rss>"#.utf8)
        expect(try lookup.sparkle(app(version: "4.0", build: "10"), data: buildXML).state == .available, "build-only feed compares CFBundleVersion")
        do { _ = try lookup.sparkle(app(), data: Data("not XML".utf8)); expect(false, "malformed feed") }
        catch { expect(true, "malformed feed") }

        expect(await lookup.check(app()).state == .failed, "network error stays visible")
        expect(await lookup.check(app(id: "org.example.unknown")).state == .unsupported, "unknown app is not up to date")
        let storeLookup = AppUpdateLookup(fetch: { url in
            guard url.host == "itunes.apple.com" else { throw UpdateLookupError.invalid("Wrong provider") }
            if url.absoluteString.contains("country=cn") { return Data(#"{"results":[]}"#.utf8) }
            return Data(#"{"results":[{"bundleId":"md.obsidian","version":"2.0","trackId":123}]}"#.utf8)
        })
        let storeResult = await storeLookup.check(app(store: true))
        expect(storeResult.state == .available && storeResult.storeID == 123, "App Store region fallback and optional fields")
        let wrongStore = AppUpdateLookup(fetch: { _ in Data(#"{"results":[{"bundleId":"another.app","version":"2","trackId":1}]}"#.utf8) })
        expect(await wrongStore.check(app(store: true)).state == .unsupported, "App Store requires exact identity")
        let fallback = AppUpdateLookup(fetch: { url in
            if url.host == "formulae.brew.sh" { return cask }
            throw URLError(.timedOut)
        })
        let fallbackResult = await fallback.check(app(feed: "https://example.org/feed.xml"))
        expect(fallbackResult.state == .available && !fallbackResult.message.isEmpty, "failed Sparkle falls back with diagnostic")
        let downloadableCask = Data(#"{"token":"obsidian","version":"2.0","homepage":"https://obsidian.md","url":"https://example.org/current.dmg","sha256":"no_check","artifacts":[{"app":["Obsidian.app",{"target":"Obsidian.app"}]}],"variations":{"arm64_sonoma":{"url":"https://example.org/compatible.dmg","sha256":"abcdef"}}}"#.utf8)
        expect(try lookup.cask(app(), token: "obsidian", data: downloadableCask).asset?.url.lastPathComponent == "compatible.dmg", "automatic downloads select matching platform variant")
        let packageCask = Data(#"{"token":"obsidian","version":"2.0","homepage":"https://obsidian.md","url":"https://example.org/install.dmg","artifacts":[{"pkg":["Install.pkg"]}]}"#.utf8)
        expect(try lookup.cask(app(), token: "obsidian", data: packageCask).asset == nil, "package casks cannot replace app bundles directly")
        var pinned = app()
        pinned.publicEDKey = "fixture-public-key"
        let signedXML = Data(#"<rss><channel><item><link>https://example.org/release-notes</link><enclosure sparkle:version="20" sparkle:shortVersionString="2.0" sparkle:edSignature="fixture-signature" url="https://example.org/app.zip"/></item></channel></rss>"#.utf8)
        let signed = try lookup.sparkle(pinned, data: signedXML)
        expect(signed.asset?.publicEDKey == "fixture-public-key" && signed.asset?.edSignature == "fixture-signature", "Sparkle pins installed app public key for download verification")
        pinned.requiresSignedFeed = true
        expect(try lookup.sparkle(pinned, data: signedXML).asset == nil, "signed-feed hosts retain their native updater")
        expect(AppUpdateAsset(url: URL(string: "https://example.org/Alfred.tar.gz")!, version: "2")?.format == .archive, "TAR app updates are supported")
        let opaqueCask = Data(#"{"token":"obsidian","version":"2.0","homepage":"https://obsidian.md","url":"https://example.org/download/osx_arm64","sha256":"no_check","artifacts":[{"app":["Obsidian.app"]}]}"#.utf8)
        expect(try lookup.cask(app(), token: "obsidian", data: opaqueCask).asset?.format == .archive, "extensionless official download keeps automatic update capability")
        print("\(passed) updater checks passed")
        let installerChecks = try await InstallerValidation.run()
        print("\(installerChecks) installer checks passed")
    }
}
