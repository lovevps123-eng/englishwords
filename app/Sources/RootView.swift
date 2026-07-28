// RootView.swift — 五 Tab 根视图：今日/单词/跟读/阅读/我的
import SwiftUI
import SwiftData

struct RootView: View {
    private enum Tab { case today, vocab, speaking, reading, settings }

    @State private var selectedTab: Tab = .today

    #if DEBUG
    @Environment(VocabStore.self) private var vocabStore
    @Query(sort: [SortDescriptor(\CachedWord.group), SortDescriptor(\CachedWord.serverId)])
    private var words: [CachedWord]
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max") }
                .tag(Tab.today)

            VocabView()
                .tabItem { Label("单词", systemImage: "rectangle.stack") }
                .tag(Tab.vocab)

            SpeakingView()
                .tabItem { Label("跟读", systemImage: "mic") }
                .tag(Tab.speaking)

            ReadingListView()
                .tabItem { Label("阅读", systemImage: "book") }
                .tag(Tab.reading)

            SettingsView()
                .tabItem { Label("我的", systemImage: "person") }
                .tag(Tab.settings)
        }
        #if DEBUG
        .task { await runSmokeSequenceIfNeeded() }
        #endif
    }

    #if DEBUG
    /// 冒烟编排器：登录成功进入五 Tab 后，依次切 Tab + 背 3 词 + 打开一篇阅读文章，
    /// 每步之间用生成宽裕的睡眠等真实网络请求（生产 API）落地，再写一个步骤 marker
    /// 供外部截图脚本轮询——marker 反映的是"数据/界面已就绪"，不是猜时间。
    private func runSmokeSequenceIfNeeded() async {
        guard SmokeAuto.isEnabled else { return }

        try? await Task.sleep(nanoseconds: 3_000_000_000)
        SmokeAuto.writeMarker("today_ready")
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        selectedTab = .vocab
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        SmokeAuto.writeMarker("vocab_unanswered")
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        for word in words.filter({ !$0.answered }).prefix(3) {
            vocabStore.submit(feedback: .know, for: word)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        SmokeAuto.writeMarker("vocab_answered")
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        selectedTab = .reading
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        SmokeAuto.writeMarker("reading_list_ready")
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        NotificationCenter.default.post(name: .smokeOpenFirstArticle, object: nil)
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        SmokeAuto.writeMarker("reading_detail_ready")
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        selectedTab = .settings
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        SmokeAuto.writeMarker("settings_ready")
    }
    #endif
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
