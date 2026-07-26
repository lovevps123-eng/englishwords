// TodayView.swift — 今日页：每日固定动作清单（背词 done/total 实时 + 跟读/阅读手动打卡）
// + study-stats 卡片（streak/learning/mastered）+ 下拉刷新。
// 背词进度用 @Query 直接观察 VocabStore 管理的 CachedWord 表（与 VocabView 同一套机制），
// 而不是调用 VocabStore.todayProgress 的一次性 fetch——@Observable 的 Observation 只追踪
// 存储属性访问，todayProgress 是计算属性内部走 SwiftData fetch，不会驱动 SwiftUI 自动刷新。
// 跟读/阅读只是手动勾选打卡，v1 不需要 SwiftData 建模，按日期 key 存 UserDefaults 足够。
import SwiftUI
import SwiftData

struct TodayView: View {
    private let apiClient: APIClient

    @Query(sort: [SortDescriptor(\CachedWord.group), SortDescriptor(\CachedWord.serverId)])
    private var words: [CachedWord]

    @State private var stats: StudyStats?
    @State private var isLoadingStats = true
    @State private var statsErrorMessage: String?

    @State private var speakingChecked = false
    @State private var readingChecked = false

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    private var vocabDone: Int { words.filter(\.answered).count }
    private var vocabTotal: Int { words.count }

    private var todayDateKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
    private var speakingDefaultsKey: String { "checkin.speaking.\(todayDateKey)" }
    private var readingDefaultsKey: String { "checkin.reading.\(todayDateKey)" }

    var body: some View {
        NavigationStack {
            List {
                Section("每日固定动作") {
                    actionRow(
                        title: "背词",
                        detail: "\(vocabDone)/\(vocabTotal) 词",
                        isDone: vocabTotal > 0 && vocabDone == vocabTotal
                    )
                    Toggle(isOn: speakingBinding) {
                        Text("跟读 15 分钟")
                    }
                    Toggle(isOn: readingBinding) {
                        Text("阅读 1 篇")
                    }
                }

                Section("学习统计") {
                    statsContent
                }
            }
            .navigationTitle("今日")
            .refreshable { await loadStats() }
            .task { await loadStats() }
            .onAppear(perform: loadCheckinState)
        }
    }

    @ViewBuilder
    private var statsContent: some View {
        if isLoadingStats {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if let statsErrorMessage {
            VStack(alignment: .leading, spacing: 4) {
                Text("加载失败")
                    .font(.subheadline)
                Text(statsErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let stats {
            HStack {
                statTile(systemImage: "flame.fill", tint: .orange, value: stats.streak, label: "连续天数")
                Spacer()
                statTile(systemImage: nil, tint: .primary, value: stats.learning, label: "学习中")
                Spacer()
                statTile(systemImage: nil, tint: .primary, value: stats.mastered, label: "已掌握")
            }
        }
    }

    private func statTile(systemImage: String?, tint: Color, value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            Text("\(value)")
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionRow(title: String, detail: String, isDone: Bool) -> some View {
        HStack {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? .green : .secondary)
            Text(title)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }

    private var speakingBinding: Binding<Bool> {
        Binding(
            get: { speakingChecked },
            set: { newValue in
                speakingChecked = newValue
                UserDefaults.standard.set(newValue, forKey: speakingDefaultsKey)
            }
        )
    }

    private var readingBinding: Binding<Bool> {
        Binding(
            get: { readingChecked },
            set: { newValue in
                readingChecked = newValue
                UserDefaults.standard.set(newValue, forKey: readingDefaultsKey)
            }
        )
    }

    private func loadCheckinState() {
        speakingChecked = UserDefaults.standard.bool(forKey: speakingDefaultsKey)
        readingChecked = UserDefaults.standard.bool(forKey: readingDefaultsKey)
    }

    private func loadStats() async {
        isLoadingStats = true
        statsErrorMessage = nil
        defer { isLoadingStats = false }
        do {
            stats = try await apiClient.get("/api/vocab/study-stats")
        } catch {
            statsErrorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Schema([CachedWord.self, PendingResult.self]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return TodayView()
        .modelContainer(container)
}
