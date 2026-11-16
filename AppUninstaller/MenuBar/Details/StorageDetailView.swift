import SwiftUI

struct StorageDetailView: View {
    @ObservedObject var manager: MenuBarManager
    @ObservedObject var diskManager = DiskSpaceManager.shared
    @ObservedObject private var loc = LocalizationManager.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(loc.text("储存空间", "Storage"))
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { 
                    withAnimation { manager.closeDetail() }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Main Chart
                    ZStack {
                        // Background Ring
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 20)
                            .frame(width: 160, height: 160)
                        
                        // Data Ring (Free Space for contrast or Used Space?)
                        // Show Used Space in Color for better visualization.
                        let usedPercent = diskManager.isAvailable ? min(1, max(0, diskManager.usagePercentage)) : 0
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(usedPercent))
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 20, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .frame(width: 160, height: 160)
                            .shadow(color: .purple.opacity(0.3), radius: 10, x: 0, y: 0)
                        
                        VStack(spacing: 4) {
                            Text(diskManager.formattedFree)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(.white)
                            Text(loc.text("可用空间", "Available"))
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                            Text(loc.text("总共 \(diskManager.formattedTotal)", "\(diskManager.formattedTotal) total"))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    }
                    .padding(.top, 10)
                    
                    VStack(spacing: 12) {
                        StorageCategoryRow(color: .blue, name: loc.text("已用空间", "Used"), size: diskManager.formattedUsed)
                        StorageCategoryRow(color: .green, name: loc.text("可用空间", "Available"), size: diskManager.formattedFree)
                        Text(loc.text("分类容量尚未采集；可打开空间透镜查看目录占用。", "Category sizes are not collected. Open Space Lens to inspect folder usage."))
                            .font(.caption).foregroundColor(.secondary)
                    }.padding(.horizontal, 20)

                    if let error = diskManager.readError {
                        Text(error).font(.caption).foregroundColor(.orange).padding(.horizontal, 20)
                    }

                    // Quick Actions
                    HStack(spacing: 12) {
                        Button(action: {
                            manager.openMainApp()
                        }) {
                            Text(loc.text("清理垃圾", "Clean Junk"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            manager.openMainApp()
                        }) {
                            Text(loc.text("管理大文件", "Manage Large Files"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 20)
            }
        }
        .background(Color(hex: "1C0C24"))
    }
}

struct StorageCategoryRow: View {
    let color: Color
    let name: String
    let size: String
    
    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Text(size)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
