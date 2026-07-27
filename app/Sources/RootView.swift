// RootView.swift — 五 Tab 根视图：今日/单词/跟读/阅读/我的
import SwiftUI
import SwiftData

struct RootView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max") }

            VocabView()
                .tabItem { Label("单词", systemImage: "rectangle.stack") }

            SpeakingView()
                .tabItem { Label("跟读", systemImage: "mic") }

            ReadingListView()
                .tabItem { Label("阅读", systemImage: "book") }

            SettingsView()
                .tabItem { Label("我的", systemImage: "person") }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Schema([CachedWord.self, PendingResult.self]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return RootView()
        .modelContainer(container)
        .environment(VocabStore(modelContext: container.mainContext))
        .environment(SettingsStore(defaults: UserDefaults(suiteName: "preview")!))
        .environment(AuthStore())
        .environment(ReadingStore())
}
