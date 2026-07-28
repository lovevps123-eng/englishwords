// EnglishWordsApp.swift — App 入口，注入 SwiftData 容器与全局 AppStore
import SwiftUI
import SwiftData

@main
struct EnglishWordsApp: App {
    let modelContainer: ModelContainer
    @State private var appStore = AppStore()
    @State private var authStore = AuthStore()
    @State private var vocabStore: VocabStore
    @State private var settingsStore = SettingsStore()
    @State private var readingStore = ReadingStore()

    init() {
        do {
            let container = try ModelContainer(for: Schema([CachedWord.self, PendingResult.self]))
            modelContainer = container
            _vocabStore = State(initialValue: VocabStore(modelContext: container.mainContext))
        } catch {
            fatalError("无法创建 SwiftData 容器: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authStore.isAuthenticated {
                    RootView()
                } else {
                    LoginView()
                }
            }
            .environment(appStore)
            .environment(authStore)
            .environment(vocabStore)
            .environment(settingsStore)
            .environment(readingStore)
            .task {
                await performStartupSyncIfNeeded()
            }
        }
        .modelContainer(modelContainer)
    }

    /// App 启动时若已是登录态，后台补交一次未同步的答题结果并刷新今日队列，让缓存尽量新鲜；
    /// 不阻塞首帧渲染（.task 与视图渲染并发），失败静默——离线可用是本 App 的设计目标
    /// （见 docs/specs/2026-07-25-english-app-refocus-design.md「错误处理」，VocabStore 同一取舍）。
    /// 未登录时不触发：这种情况下 sync/refreshQueue 请求会因缺 token 直接 401，没有意义。
    private func performStartupSyncIfNeeded() async {
        guard authStore.isAuthenticated else { return }
        await vocabStore.sync()
        try? await vocabStore.refreshQueue(tier: settingsStore.tier, newLimit: settingsStore.dailyNewLimit)
    }
}

/// 全局应用状态占位，后续任务会挂载登录态、设置等
@Observable
final class AppStore {
}
