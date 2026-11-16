import SwiftUI

struct SettingsView: View {
    @ObservedObject var loc = LocalizationManager.shared
    @StateObject private var updateService = UpdateCheckerService.shared
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @State private var showAISettings = false
    
    // Environment to close the sheet/window
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(t("设置", "設定", "Settings", "設定", "설정", "Настройки"))
                    .font(.title2)
                    .bold()
                Spacer()
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark")
                        .foregroundColor(.gray)
                        .padding(5)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.black.opacity(0.2))
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // App Info Section
                    VStack(alignment: .center, spacing: 12) {
                        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                            .resizable()
                            .frame(width: 80, height: 80)
                        
                        Text(loc.currentLanguage.productName)
                            .font(.headline)
                        
                        Text("\(t("版本", "版本", "Version", "バージョン", "버전", "Версия")) \(updateService.currentVersionDisplay)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    
                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("Mac 优化智能体", "Mac 最佳化智慧代理", "Mac Optimization Agent", "Mac最適化エージェント", "Mac 최적화 에이전트", "Агент оптимизации Mac"))
                            .font(.headline)

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(AIProviderSettingsStore.shared.activeProvider.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(t("配置服务地址、模型和 API Key", "設定服務位址、模型與 API Key", "Configure endpoint, model, and API key", "エンドポイント、モデル、APIキーを設定", "서비스 주소, 모델 및 API 키 설정", "Настройка адреса, модели и API-ключа"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(t("打开设置", "開啟設定", "Open Settings", "設定を開く", "설정 열기", "Открыть настройки")) {
                                showAISettings = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                    }

                    Divider().opacity(0.5)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(t("语言", "語言", "Language", "言語", "언어", "Язык"))
                            .font(.headline)

                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(loc.currentLanguage.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(t(
                                    "更改后立即应用到整个应用；系统权限文字会在重启后更新",
                                    "變更後會立即套用到整個應用程式；系統權限文字會在重新啟動後更新",
                                    "Changes apply immediately; system permission text updates after relaunch",
                                    "変更はすぐにアプリ全体へ反映されます。システム権限の表示は再起動後に更新されます",
                                    "변경 사항은 앱 전체에 즉시 적용되며 시스템 권한 문구는 재실행 후 업데이트됩니다",
                                    "Изменения применяются сразу; текст системных разрешений обновится после перезапуска"
                                ))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: Binding(
                                get: { loc.currentLanguage },
                                set: { loc.setLanguage($0) }
                            )) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text("\(language.flag) \(language.displayName)").tag(language)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                    }

                    Divider().opacity(0.5)
                    
                    updateSection
                }
                .padding(24)
            }
        }
        .frame(width: 520, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.async {
                AppMenuLocalizer.apply(loc.currentLanguage)
            }
            if autoCheckUpdates && updateService.state == .notChecked && !updateService.isChecking {
                Task {
                    await updateService.checkForUpdates()
                }
            }
        }
        .sheet(isPresented: $showAISettings) {
            AIAssistantSettingsView {
                showAISettings = false
            }
            .frame(width: 620, height: 540)
            .background(Color(nsColor: .windowBackgroundColor))
            .preferredColorScheme(.dark)
        }
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.text("软件更新", "Software Update")).font(.headline)
            Toggle(loc.text("启动时自动检查更新", "Automatically check for updates at launch"), isOn: $autoCheckUpdates)
                .toggleStyle(.switch)
            Text(updateService.statusText).foregroundColor(updateService.hasUpdate ? .green : .secondary)
            if let error = updateService.errorMessage {
                Text(error).font(.caption).foregroundColor(.orange).textSelection(.enabled)
            }
            if let source = updateService.sourceText {
                Text(source).font(.caption).foregroundColor(.secondary)
            }
            if let retry = updateService.apiRetryAt, retry > Date() {
                Text(loc.text("GitHub 接口限流，暂停请求至：", "GitHub API rate limited; paused until: ") + retry.formatted(date: .abbreviated, time: .standard))
                    .font(.caption).foregroundColor(.secondary)
            }
            if let checked = updateService.checkedAt {
                Text(loc.text("上次成功检查：", "Last successful check: ") + checked.formatted(date: .abbreviated, time: .standard))
                    .font(.caption).foregroundColor(.secondary)
            }
            Text(loc.text("更新渠道：", "Release channel: ") + updateService.repository)
                .font(.caption).foregroundColor(.secondary)
            if updateService.hasUpdate && !updateService.releaseNotes.isEmpty {
                Text(updateService.releaseNotes).font(.caption).foregroundColor(.secondary).lineLimit(4)
            }
            HStack {
                if updateService.isChecking {
                    ProgressView().controlSize(.small)
                    Button(loc.text("停止检查", "Stop Checking")) { updateService.cancelCheck() }
                } else {
                    Button(loc.text("检查更新", "Check for Updates")) { Task { await updateService.checkForUpdates() } }
                }
                if updateService.hasUpdate, let url = updateService.downloadURL {
                    Button(loc.text("查看发布页", "Open Release Page")) { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    private func t(
        _ simplifiedChinese: String,
        _ traditionalChinese: String,
        _ english: String,
        _ japanese: String,
        _ korean: String,
        _ russian: String
    ) -> String {
        loc.text(
            simplifiedChinese: simplifiedChinese,
            traditionalChinese: traditionalChinese,
            english: english,
            japanese: japanese,
            korean: korean,
            russian: russian
        )
    }
}
