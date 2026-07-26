// VocabView.swift — 单词 Tab 主页面：加载/失败态 → 卡片流（认识/模糊/不认识）→ 完成态。
// 用 @Query 直接观察 CachedWord（而非 VocabStore.todayProgress 的一次性 fetch），
// 这样 submit() 落盘后视图自动重新计算，无需手动通知。
import SwiftUI
import SwiftData

struct VocabView: View {
    @Environment(VocabStore.self) private var store

    @Query(sort: [SortDescriptor(\CachedWord.group), SortDescriptor(\CachedWord.serverId)])
    private var words: [CachedWord]

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var syncMessage: String?
    @State private var speechService = SpeechService()

    // TODO(Task 5): tier/newLimit 应来自设置页；设置 UI 落地前先用固定值。
    private let tier = 1
    private let newLimit = 50

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
                    await store.sync()
                    syncMessage = "同步完成"
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
                    .foregroundStyle(.green)
            }
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
    private func loadIfNeeded(force: Bool = false) async {
        guard force || words.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await store.refreshQueue(tier: tier, newLimit: newLimit)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
