// VocabView.swift — 单词 Tab 主页面：加载/失败态 → 卡片流（认识/模糊/不认识）→ 完成态。
// 用 @Query 直接观察 CachedWord（而非 VocabStore.todayProgress 的一次性 fetch），
// 这样 submit() 落盘后视图自动重新计算，无需手动通知。
import SwiftUI
import SwiftData

struct VocabView: View {
    @Environment(VocabStore.self) private var store
    @Environment(SettingsStore.self) private var settings

    @Query(sort: [SortDescriptor(\CachedWord.group), SortDescriptor(\CachedWord.serverId)])
    private var words: [CachedWord]

    // 初始 true：首次渲染时队列尚未拉取，避免瞬间先看到（错误的）空态/完成态文案再跳到加载中。
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var syncMessage: String?
    @State private var syncFailed = false
    @State private var speechService = SpeechService()

    private var unansweredWords: [CachedWord] {
        words.filter { !$0.answered }
    }

    private var progress: (done: Int, total: Int) {
        (words.count - unansweredWords.count, words.count)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("单词")
                .task { await loadIfNeeded() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("正在加载今日单词…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            errorView(errorMessage)
        } else if let currentWord = unansweredWords.first {
            VStack(spacing: 16) {
                progressBar
                WordCardView(
                    word: currentWord,
                    speechService: speechService,
                    onFeedback: { feedback in
                        store.submit(feedback: feedback, for: currentWord)
                    }
                )
                .id(currentWord.persistentModelID)
            }
            .padding()
        } else if words.isEmpty {
            emptyQueueView
        } else {
            completionView
        }
    }

    private var progressBar: some View {
        let snapshot = progress
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(snapshot.done), total: Double(max(snapshot.total, 1)))
            Text("\(snapshot.done)/\(snapshot.total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var completionView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("今日完成 🎉")
                .font(.title.bold())
            Text("已背 \(progress.total) 词")
                .foregroundStyle(.secondary)

            Button {
                Task {
                    if let result = await store.sync() {
                        syncFailed = false
                        syncMessage = "已同步 \(result.processed) 条"
                    } else {
                        syncFailed = true
                        syncMessage = "同步失败，稍后自动重试"
                    }
                }
            } label: {
                Text("同步")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)

            if let syncMessage {
                Text(syncMessage)
                    .font(.footnote)
                    .foregroundStyle(syncFailed ? .red : .green)
            }
            Spacer()
        }
        .padding()
    }

    /// 队列本身为空（服务端今日无新词/复习词可学），区别于"已作答完毕"的完成态。
    private var emptyQueueView: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("今日没有需要学习的词，去阅读逛逛吧")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text("加载失败")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("重试") {
                Task { await loadIfNeeded(force: true) }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    /// 仅当本地完全没有缓存队列时自动拉取；force: true 用于重试按钮（错误态下 words 也可能为空）。
    /// guard 提前返回也要把 isLoading 收尾成 false——否则初始值 true 会在"本地已有缓存、
    /// 本次不需要拉取"的路径上卡住，永远停在加载中转不到卡片/完成态。
    private func loadIfNeeded(force: Bool = false) async {
        guard force || words.isEmpty else {
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await store.refreshQueue(tier: settings.tier, newLimit: settings.dailyNewLimit)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
