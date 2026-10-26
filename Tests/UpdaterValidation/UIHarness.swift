import SwiftUI
import AppKit
import CryptoKit

@main
struct UpdaterUIValidationApp: App {
    @StateObject private var service: AppUpdaterService
    private let directory: URL

    init() {
        let setup = try! UIValidationFixtures.make()
        directory = setup.0
        _service = StateObject(wrappedValue: setup.1)
    }

    var body: some Scene {
        WindowGroup("更新模块验证") {
            AppUpdaterView(service: service)
                .frame(minWidth: 760, minHeight: 500)
                .background(Color(white: 0.12))
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    try? FileManager.default.removeItem(at: directory)
                }
        }
        .defaultSize(width: 820, height: 620)
    }
}

private enum UIValidationFixtures {
    @MainActor
    static func make() throws -> (URL, AppUpdaterService) {
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("MacOptimizerUITests-\(UUID().uuidString)").resolvingSymlinksInPath()
        let apps = directory.appendingPathComponent("Applications")
        try manager.createDirectory(at: apps, withIntermediateDirectories: true)
        var records: [AppUpdateRecord] = []
        for (key, name) in [("success", "安装成功测试"), ("failure", "安装失败回滚测试"), ("cancel", "取消下载测试")] {
            let id = "org.example.MacOptimizerUIFixture." + key
            let original = apps.appendingPathComponent(name + ".app")
            let payload = directory.appendingPathComponent(key + "/Payload")
            let next = payload.appendingPathComponent(name + ".app")
            try makeBundle(original, id: id, name: name, version: "1.0", build: "10")
            try makeBundle(next, id: id, name: name, version: "2.0", build: "20")
            let archive = directory.appendingPathComponent(key + ".zip")
            _ = try AppUpdateCommand.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", payload.path, archive.path])
            let hash = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
            let asset = AppUpdateAsset(url: URL(string: "https://example.invalid/" + key + ".zip")!, version: "2.0", build: "20", sha256: hash)!
            var check = UpdateCheck(state: .available, source: "临时测试文件", version: "2.0", url: URL(string: "https://example.invalid"))
            check.asset = asset
            records.append(AppUpdateRecord(application: UpdateApplication.read(at: original)!, check: check,
                                           icon: NSWorkspace.shared.icon(forFile: original.path), automaticUpdateUnavailableReason: nil))
        }
        let installer = AppUpdateInstaller(roots: [apps], download: { url, destination, progress in
            let steps = url.lastPathComponent == "cancel.zip" ? 120 : 20
            for step in 0...steps {
                try Task.checkCancellation()
                progress(Double(step) / Double(steps))
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            try FileManager.default.copyItem(at: directory.appendingPathComponent(url.lastPathComponent), to: destination)
        }, verify: { candidate, app, asset, _ in
            // Only this separate test executable accepts unsigned temporary fixture bundles.
            try AppUpdateVerifier.validateMetadata(candidate, application: app, asset: asset)
            if app.bundleID.hasSuffix(".failure"), candidate == app.path {
                throw AppUpdateInstallError.rejected("模拟安装校验失败")
            }
        })
        return (directory, AppUpdaterService(installer: installer, initialRecords: records))
    }

    private static func makeBundle(_ url: URL, id: String, name: String, version: String, build: String) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try manager.copyItem(at: Bundle.main.executableURL!, to: url.appendingPathComponent("Contents/MacOS/Fixture"))
        let info = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundleExecutable": "Fixture",
                    "CFBundleShortVersionString": version, "CFBundleVersion": build, "LSMinimumSystemVersion": "13.0"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: url.appendingPathComponent("Contents/Info.plist"))
    }
}
