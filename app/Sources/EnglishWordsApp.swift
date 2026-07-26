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
        }
        .modelContainer(modelContainer)
    }
}

/// 全局应用状态占位，后续任务会挂载登录态、设置等
@Observable
final class AppStore {
}
