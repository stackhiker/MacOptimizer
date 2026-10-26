import SwiftUI
import AppKit

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    func text(_ chinese: String, _ english: String) -> String { chinese }
}

struct InstalledApp {
    let name: String
    let path: URL
    let bundleIdentifier: String?
    let icon: NSImage
    let size: Int64
    let isAppStore: Bool
    let version: String?
}
