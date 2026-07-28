// SettingsView.swift — 我的页：难度档/每日新词量/服务器地址/登出。
// tier、dailyNewLimit 改动后调用 VocabStore.refreshQueue 让今日队列跟随新设置——
// refreshQueue 已在 Task 3 保证不会冲掉未同步的已答状态，可安全随时调用。
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AuthStore.self) private var authStore
    @Environment(VocabStore.self) private var vocabStore

    @State private var showLogoutConfirm = false
    @State private var serverURLHint: String?
    @State private var queueRefreshErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("难度档", selection: tierBinding) {
                        Text("基础").tag(1)
                        Text("拔高").tag(2)
                    }

                    Stepper(value: dailyNewLimitBinding, in: 10...100, step: 10) {
                        HStack {
                            Text("每日新词量")
                            Spacer()
                            Text("\(settings.dailyNewLimit)")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let queueRefreshErrorMessage {
                        Text(queueRefreshErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("学习设置")
                }

                Section {
                    TextField("服务器地址", text: serverBaseURLBinding)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let serverURLHint {
                        Text(serverURLHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("服务器")
                }

                Section {
                    Button("登出", role: .destructive) {
                        showLogoutConfirm = true
                    }
                }
            }
            .navigationTitle("我的")
            .confirmationDialog(
                "确定要登出吗？", isPresented: $showLogoutConfirm, titleVisibility: .visible
            ) {
                Button("登出", role: .destructive) {
                    // 主动登出：换账号场景，必须先清本地词库缓存 + 待同步队列 + 打卡状态，
                    // 否则新账号会看到旧账号的缓存词（VocabView.loadIfNeeded 因非空跳过拉取），
                    // 更严重的是旧账号未同步的 PendingResult 会用新账号的 token 提交，
                    // 污染新账号的服务端 SRS 数据（不可逆）。区别于 401 强制登出（同账号 token
                    // 过期），那条路径不清数据，见 VocabStore.clearAllLocalData() 注释。
                    vocabStore.clearAllLocalData()
                    clearAllCheckinState()
                    authStore.logout()
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private var tierBinding: Binding<Int> {
        Binding(
            get: { settings.tier },
            set: { newValue in
                settings.tier = newValue
                Task { await refreshQueueAfterSettingsChange() }
            }
        )
    }

    private var dailyNewLimitBinding: Binding<Int> {
        Binding(
            get: { settings.dailyNewLimit },
            set: { newValue in
                settings.dailyNewLimit = newValue
                Task { await refreshQueueAfterSettingsChange() }
            }
        )
    }

    private var serverBaseURLBinding: Binding<String> {
        Binding(
            get: { settings.serverBaseURL },
            set: { newValue in
                settings.serverBaseURL = newValue
                serverURLHint = "已保存，重启 App 后生效"
            }
        )
    }

    /// 按前缀 "checkin." 遍历删除 TodayView 的跟读/阅读打卡 UserDefaults key（各日期各一条）。
    private func clearAllCheckinState() {
        let defaults = UserDefaults.standard
        let keysToRemove = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("checkin.") }
        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
    }

    private func refreshQueueAfterSettingsChange() async {
        do {
            try await vocabStore.refreshQueue(tier: settings.tier, newLimit: settings.dailyNewLimit)
            queueRefreshErrorMessage = nil
        } catch {
            queueRefreshErrorMessage = "刷新今日队列失败："
                + ((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Schema([CachedWord.self, PendingResult.self]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return SettingsView()
        .modelContainer(container)
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(AuthStore())
        .environment(VocabStore(modelContext: container.mainContext))
}
