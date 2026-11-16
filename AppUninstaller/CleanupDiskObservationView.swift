import SwiftUI

struct CleanupDiskObservationView: View {
    let change: Int64?
    @ObservedObject private var loc = LocalizationManager.shared

    var body: some View {
        if let change {
            let amount = ByteCountFormatter.string(fromByteCount: change, countStyle: .file)
            Text(loc.text("磁盘可用空间变化：", "Observed disk free-space change: ")
                 + (change > 0 ? "+" : "") + amount
                 + loc.text("（包含其他系统活动）", " (includes other system activity)"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
