// EnglishWordsApp.swift — App 入口，注入 SwiftData 容器与全局 AppStore
import SwiftUI
import SwiftData

@main
struct EnglishWordsApp: App {
    let modelContainer: ModelContainer
    @State private var appStore = AppStore()
    @State private var authStore = AuthStore()

    init() {
        // 当前无 @Model 类型，后续任务（单词离线队列等）会追加 schema
        do {
            modelContainer = try ModelContainer(for: Schema([]))
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
        }
        .modelContainer(modelContainer)
    }
}

/// 全局应用状态占位，后续任务会挂载登录态、设置等
@Observable
final class AppStore {
}
