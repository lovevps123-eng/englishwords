// SpeakingView.swift — 跟读 Tab 主页面：复用 spike/Sources/ContentView.swift 验证过的交互
// （目标句 → 录音 → 逐词红绿高亮 → 得分），练习材料换成当日已缓存词的例句（CachedWord.examplesJSON
// 第一条 en，见 SpeakingStore.extractSentences），并加"下一句"流转 + 已练习计数。
// 用 @Query 直接观察 CachedWord（与 VocabView/TodayView 同一套机制），这样 VocabView 答题、
// refreshQueue 刷新队列后，可练习的例句列表会自动跟着变，不需要手动通知。
import SwiftUI
import SwiftData

struct SpeakingView: View {
    @Query(sort: [SortDescriptor(\CachedWord.group), SortDescriptor(\CachedWord.serverId)])
    private var words: [CachedWord]

    @State private var store = SpeakingStore()
    @StateObject private var recognizer = Recognizer()

    private var sentences: [String] { SpeakingStore.extractSentences(from: words) }

    private var currentTarget: String? {
        guard !sentences.isEmpty else { return nil }
        // 句子列表可能因 @Query 更新而变短：越界时兜底回第一句，而不是崩溃/空白。
        let index = min(store.currentIndex, sentences.count - 1)
        return sentences[index]
    }

    private var diff: WordDiff.Result {
        guard let target = currentTarget else { return [] }
        return store.diff(target: target, recognized: recognizer.transcript)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let target = currentTarget {
                    practiceContent(target: target)
                } else {
                    emptyView
                }
            }
            .padding()
            .navigationTitle("跟读")
        }
    }

    @ViewBuilder
    private func practiceContent(target: String) -> some View {
        VStack(spacing: 24) {
            Text(target)
                .font(.title3)
                .multilineTextAlignment(.center)

            // 逐词高亮：绿=读中，红=漏/错
            diff.reduce(Text("")) { acc, item in
                acc + Text(item.word + " ").foregroundColor(item.hit ? .green : .red)
            }
            .font(.title2)

            Text("识别结果：\(recognizer.transcript)")
                .foregroundStyle(.secondary)

            Text("得分：\(store.score(diff: diff))")
                .font(.largeTitle.bold())

            if let err = recognizer.errorMessage {
                Text(err).foregroundStyle(.orange)
            }

            Button(recognizer.isRecording ? "停止" : "开始跟读") {
                recognizer.isRecording ? recognizer.stop() : recognizer.start()
            }
            .buttonStyle(.borderedProminent)

            Button("下一句") {
                recognizer.stop()
                // 必须清空上一句的识别文本：否则新目标句会和上一句的 transcript 拼出
                // 误导性的红绿高亮/得分，直到用户重新点"开始跟读"才会自愈。
                recognizer.reset()
                store.advance(sentenceCount: sentences.count)
            }
            .buttonStyle(.bordered)

            Text("已练习 \(store.practicedCount) 句")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("今日暂无可练习的例句")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("先去「单词」背几个词，或等今日队列加载完成")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Schema([CachedWord.self, PendingResult.self]),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return SpeakingView()
        .modelContainer(container)
}
