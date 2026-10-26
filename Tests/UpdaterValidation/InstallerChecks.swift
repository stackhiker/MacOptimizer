import Foundation
import CryptoKit

struct InstallerValidation {
    static func run() async throws -> Int {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("MacOptimizerInstallerTests-\(UUID().uuidString)").resolvingSymlinksInPath()
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        guard let executable = ProcessInfo.processInfo.environment["MACOPTIMIZER_FIXTURE_EXECUTABLE"] else {
            fatalError("Run these tests through validate-updater.sh")
        }
        var passed = 0
        func expect(_ condition: Bool, _ name: String) {
            guard condition else { fatalError("FAIL: \(name)") }
            passed += 1
            print("PASS: \(name)")
        }
        func makeApp(_ url: URL, version: String, id: String = "org.example.MacOptimizerFixture") throws {
            try manager.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let binary = url.appendingPathComponent("Contents/MacOS/Fixture")
            if !manager.fileExists(atPath: binary.path) { try manager.copyItem(atPath: executable, toPath: binary.path) }
            let info = ["CFBundleIdentifier": id, "CFBundleName": "Fixture", "CFBundleExecutable": "Fixture",
                        "CFBundleShortVersionString": version, "CFBundleVersion": version + "0", "LSMinimumSystemVersion": "13.0"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
            try Data("Version \(version)".utf8).write(to: url.appendingPathComponent("Contents/Fixture.txt"))
        }
        func fixture(_ name: String, newVersion: String = "2.0", newID: String = "org.example.MacOptimizerFixture") throws -> (URL, UpdateApplication, URL) {
            let folder = root.appendingPathComponent(name)
            let apps = folder.appendingPathComponent("Applications")
            let payload = folder.appendingPathComponent("Payload")
            try manager.createDirectory(at: apps, withIntermediateDirectories: true)
            try manager.createDirectory(at: payload, withIntermediateDirectories: true)
            let original = apps.appendingPathComponent("Fixture '$ & (literal).app")
            try makeApp(original, version: "1.0")
            try makeApp(payload.appendingPathComponent("New Fixture.app"), version: newVersion, id: newID)
            let archive = folder.appendingPathComponent("fixture.zip")
            _ = try AppUpdateCommand.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", payload.path, archive.path])
            return (apps, UpdateApplication.read(at: original)!, archive)
        }
        func asset(for archive: URL, format: String = "zip") throws -> AppUpdateAsset {
            let hash = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
            return AppUpdateAsset(url: URL(string: "https://example.org/fixture.\(format)")!, version: "2.0", build: "2.00", sha256: hash)!
        }
        func installer(apps: URL, archive: URL, failAfterReplacement: Bool = false, failStaging: Bool = false) -> AppUpdateInstaller {
            AppUpdateInstaller(roots: [apps], download: { _, destination, progress in
                try FileManager.default.copyItem(at: archive, to: destination)
                progress(1)
            }, verify: { candidate, app, asset, _ in
                // Fixture apps are deliberately unsigned; production always uses AppUpdateVerifier.validate.
                try AppUpdateVerifier.validateMetadata(candidate, application: app, asset: asset)
                if failAfterReplacement && candidate == app.path {
                    throw AppUpdateInstallError.rejected("Injected post-install failure")
                }
                if failStaging && candidate.lastPathComponent == "New.app" {
                    throw AppUpdateInstallError.rejected("Injected staging failure")
                }
            })
        }
        func expectFailure(_ name: String, _ operation: () async throws -> Void) async {
            do { try await operation(); expect(false, name) }
            catch { expect(true, name) }
        }

        let (apps, original, archive) = try fixture("success")
        let updateAsset = try asset(for: archive)
        let engine = installer(apps: apps, archive: archive)
        let prepared = try await engine.prepare(application: original, asset: updateAsset) { _ in }
        expect(UpdateApplication.read(at: original.path)?.version == "1.0", "preparation leaves installed app untouched")
        let backup = try await engine.install(prepared) { _ in }
        expect(UpdateApplication.read(at: original.path)?.version == "2.0", "ZIP update replaces the fixture app")
        expect(UpdateApplication.read(at: backup)?.version == "1.0", "successful update retains the exact original")
        expect(!manager.fileExists(atPath: prepared.directory.path), "successful install cleans staging downloads")
        expect(try String(contentsOf: backup.appendingPathComponent("Contents/Fixture.txt"), encoding: .utf8) == "Version 1.0", "original bundle contents remain intact")

        let (rollbackApps, rollbackApp, rollbackArchive) = try fixture("rollback")
        let rollback = installer(apps: rollbackApps, archive: rollbackArchive, failAfterReplacement: true)
        let rollbackPrepared = try await rollback.prepare(application: rollbackApp, asset: asset(for: rollbackArchive)) { _ in }
        await expectFailure("post-install failure is reported") { _ = try await rollback.install(rollbackPrepared) { _ in } }
        expect(UpdateApplication.read(at: rollbackApp.path)?.version == "1.0", "post-install failure automatically restores original")

        let (stagingApps, stagingApp, stagingArchive) = try fixture("staging")
        let staging = installer(apps: stagingApps, archive: stagingArchive, failStaging: true)
        let stagingPrepared = try await staging.prepare(application: stagingApp, asset: asset(for: stagingArchive)) { _ in }
        await expectFailure("staging verification failure is reported") { _ = try await staging.install(stagingPrepared) { _ in } }
        expect(UpdateApplication.read(at: stagingApp.path)?.version == "1.0", "staging failure never removes original")

        let (staleApps, staleApp, staleArchive) = try fixture("stale")
        let stale = installer(apps: staleApps, archive: staleArchive)
        let stalePrepared = try await stale.prepare(application: staleApp, asset: asset(for: staleArchive)) { _ in }
        try makeApp(staleApp.path, version: "1.5")
        await expectFailure("concurrent application update invalidates transaction") { _ = try await stale.install(stalePrepared) { _ in } }
        expect(UpdateApplication.read(at: staleApp.path)?.version == "1.5", "concurrent changes are preserved")

        let (runningApps, runningApp, runningArchive) = try fixture("reopened")
        let runningEngine = AppUpdateInstaller(roots: [runningApps], download: { _, destination, _ in
            try FileManager.default.copyItem(at: runningArchive, to: destination)
        }, verify: { candidate, app, asset, _ in
            try AppUpdateVerifier.validateMetadata(candidate, application: app, asset: asset)
        }, isRunning: { _ in true })
        let runningPrepared = try await runningEngine.prepare(application: runningApp, asset: asset(for: runningArchive)) { _ in }
        await expectFailure("application reopened during staging prevents replacement") {
            _ = try await runningEngine.install(runningPrepared) { _ in }
        }
        expect(UpdateApplication.read(at: runningApp.path)?.version == "1.0", "running application remains untouched")

        for (name, version, identity) in [("wrong-version", "3.0", "org.example.MacOptimizerFixture"),
                                          ("wrong-identity", "2.0", "org.example.OtherFixture"),
                                          ("downgrade", "0.9", "org.example.MacOptimizerFixture")] {
            let (directory, app, zip) = try fixture(name, newVersion: version, newID: identity)
            let checker = installer(apps: directory, archive: zip)
            var download = try asset(for: zip)
            if name == "downgrade" { download = AppUpdateAsset(url: download.url, version: "0.9")! }
            let downloadAsset = download
            await expectFailure("reject \(name)") { _ = try await checker.prepare(application: app, asset: downloadAsset) { _ in } }
            expect(UpdateApplication.read(at: app.path)?.version == "1.0", "\(name) leaves original intact")
        }

        let (_, signedApp, _) = try fixture("unsigned")
        let unsignedCandidate = root.appendingPathComponent("unsigned/Payload/New Fixture.app")
        await expectFailure("production trust validator rejects unsigned fixture") {
            try AppUpdateVerifier.validate(unsignedCandidate, application: signedApp, asset: updateAsset, original: signedApp.path)
        }
        let outsideLink = unsignedCandidate.appendingPathComponent("Contents/Outside")
        try manager.createSymbolicLink(at: outsideLink, withDestinationURL: root)
        await expectFailure("reject links pointing outside the new app") {
            try AppUpdateVerifier.validateMetadata(unsignedCandidate, application: signedApp, asset: updateAsset)
        }

        var badChecksum = updateAsset
        badChecksum.sha256 = String(repeating: "0", count: 64)
        let rejectedChecksum = badChecksum
        await expectFailure("reject archive checksum mismatch") { try AppUpdateVerifier.verifyArchive(archive, asset: rejectedChecksum) }
        try AppUpdateVerifier.verifyArchive(archive, asset: updateAsset)
        expect(true, "accept matching SHA-256 archive")
        let key = Curve25519.Signing.PrivateKey()
        var signedAsset = updateAsset
        signedAsset.publicEDKey = key.publicKey.rawRepresentation.base64EncodedString()
        signedAsset.edSignature = try key.signature(for: Data(contentsOf: archive)).base64EncodedString()
        try AppUpdateVerifier.verifyArchive(archive, asset: signedAsset)
        expect(true, "accept valid Sparkle Ed25519 archive signature")
        signedAsset.edSignature = Data(count: 64).base64EncodedString()
        let invalidSignature = signedAsset
        await expectFailure("reject invalid Sparkle archive signature") { try AppUpdateVerifier.verifyArchive(archive, asset: invalidSignature) }
        signedAsset.edSignature = nil
        let missingSignature = signedAsset
        await expectFailure("require signature when installed app pins a public key") { try AppUpdateVerifier.verifyArchive(archive, asset: missingSignature) }
        expect(AppUpdateAsset(url: URL(string: "https://example.org/install.pkg")!, version: "2") == nil, "packages retain official installer workflow")
        expect(AppUpdateAsset(url: URL(string: "http://example.org/install.zip")!, version: "2") == nil, "automatic downloads require HTTPS")

        for path in ["../outside", "/absolute/path", "safe/../../outside", "bad\\path", "line\nbreak"] {
            expect(!AppUpdateInstaller.safeArchivePath(path), "reject unsafe archive entry \(path.debugDescription)")
        }
        expect(AppUpdateInstaller.safeArchivePath("./Fixture.app/Contents/Info.plist"), "accept ordinary relative archive entries")

        let (cancelApps, cancelApp, _) = try fixture("cancel")
        let gate = InstallerDownloadGate()
        let cancelEngine = AppUpdateInstaller(roots: [cancelApps], download: { _, destination, _ in
            await gate.enter(destination)
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }, verify: { _, _, _, _ in })
        let cancelled = Task { try await cancelEngine.prepare(application: cancelApp, asset: updateAsset) { _ in } }
        while await gate.destination == nil { try await Task.sleep(nanoseconds: 1_000_000) }
        cancelled.cancel()
        await expectFailure("cancellation stops preparation") { _ = try await cancelled.value }
        expect(UpdateApplication.read(at: cancelApp.path)?.version == "1.0", "cancellation never changes installed app")
        let cancelledDirectory = await gate.destination!.deletingLastPathComponent()
        expect(!manager.fileExists(atPath: cancelledDirectory.path), "cancelled downloads are cleaned")

        let (tarApps, tarApp, _) = try fixture("tar")
        let tar = root.appendingPathComponent("tar/fixture.tar.gz")
        _ = try AppUpdateCommand.run("/usr/bin/tar", ["-czf", tar.path, "-C", root.appendingPathComponent("tar/Payload").path, "."])
        let tarEngine = installer(apps: tarApps, archive: tar)
        let tarPrepared = try await tarEngine.prepare(application: tarApp, asset: asset(for: tar, format: "tar.gz")) { _ in }
        _ = try await tarEngine.install(tarPrepared) { _ in }
        expect(UpdateApplication.read(at: tarApp.path)?.version == "2.0", "TAR archive installs its app bundle")

        let (unsafeApps, unsafeApp, _) = try fixture("traversal")
        let unsafeTar = root.appendingPathComponent("traversal/unsafe.tar.gz")
        _ = try AppUpdateCommand.run("/usr/bin/tar", ["-czf", unsafeTar.path, "-C", root.appendingPathComponent("traversal/Payload").path, "-s", "|^|../|", "."])
        let unsafeEngine = installer(apps: unsafeApps, archive: unsafeTar)
        await expectFailure("archive traversal fails before installation") {
            _ = try await unsafeEngine.prepare(application: unsafeApp, asset: asset(for: unsafeTar, format: "tar.gz")) { _ in }
        }
        expect(UpdateApplication.read(at: unsafeApp.path)?.version == "1.0", "archive traversal preserves original app")

        let (dmgApps, dmgApp, _) = try fixture("dmg")
        let dmg = root.appendingPathComponent("dmg/fixture.dmg")
        _ = try AppUpdateCommand.run("/usr/bin/hdiutil", ["create", "-srcfolder", root.appendingPathComponent("dmg/Payload").path,
                                                        "-volname", "UpdaterFixture", "-format", "UDZO", dmg.path])
        let dmgEngine = installer(apps: dmgApps, archive: dmg)
        let dmgPrepared = try await dmgEngine.prepare(application: dmgApp, asset: asset(for: dmg, format: "dmg")) { _ in }
        let mounted = manager.mountedVolumeURLs(includingResourceValuesForKeys: nil) ?? []
        expect(!mounted.contains(where: { $0.path.hasPrefix(dmgPrepared.directory.path) }), "DMG is detached after preparing its app")
        _ = try await dmgEngine.install(dmgPrepared) { _ in }
        expect(UpdateApplication.read(at: dmgApp.path)?.version == "2.0", "DMG update installs the fixture app")
        let opaqueAsset = AppUpdateAsset(url: URL(string: "https://example.org/download?platform=mac")!, version: "2.0", build: "2.00",
                                        sha256: try asset(for: dmg, format: "dmg").sha256, allowOpaqueURL: true)!
        let opaqueApp = UpdateApplication.read(at: dmgApp.path)!
        try makeApp(dmgApp.path, version: "1.0")
        let opaqueOriginal = UpdateApplication.read(at: opaqueApp.path)!
        let opaquePrepared = try await dmgEngine.prepare(application: opaqueOriginal, asset: opaqueAsset) { _ in }
        _ = try await dmgEngine.install(opaquePrepared) { _ in }
        expect(UpdateApplication.read(at: opaqueOriginal.path)?.version == "2.0", "extensionless download detects and installs disk image")
        return passed
    }
}

private actor InstallerDownloadGate {
    var destination: URL?
    func enter(_ destination: URL) { self.destination = destination }
}
