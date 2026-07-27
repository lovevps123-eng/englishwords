// SpeakingStore.swift — 跟读模块状态：持有可替换的 ScoringStrategy（默认 StrictScoring，
// spike 结论出来后只换这里的默认值），并管理"当前第几句/已练习计数"这两项与 UI 数据源
// 无关的纯状态。练习材料本身（CachedWord → 例句）由 extractSentences 静态方法从 @Query
// 结果派生，不在 Store 里另存一份列表副本——避免和 SwiftData 的 @Query 结果产生第二个
// 真相来源（对齐 TodayView.swift 顶部注释里"@Observable 计算属性不会驱动 @Query 自动刷新"
// 的教训：Store 不做一次性 fetch，句子列表交给 View 层的 @Query 驱动）。
import Foundation

@Observable
final class SpeakingStore {
    var strategy: ScoringStrategy

    private(set) var currentIndex = 0
    private(set) var practicedCount = 0

    init(strategy: ScoringStrategy = StrictScoring()) {
        self.strategy = strategy
    }

    func diff(target: String, recognized: String) -> WordDiff.Result {
        WordDiff.diff(target: target, recognized: recognized)
    }

    func score(diff: WordDiff.Result) -> Int {
        strategy.score(diff: diff)
    }

    /// 一句练完，"下一句"流转：练习计数 +1，索引推进到下一句（循环）。
    /// sentenceCount 由调用方（View）传入当前可练习的句子总数——Store 本身不持有句子列表，
    /// 避免和 @Query 结果的句子数量不一致。
    func advance(sentenceCount: Int) {
        practicedCount += 1
        guard sentenceCount > 0 else { currentIndex = 0; return }
        currentIndex = (currentIndex + 1) % sentenceCount
    }

    /// 当日已缓存词的英文例句列表：examplesJSON 取第一条 en 作为练习句，无例句（数组为空/
    /// 解码失败/en 为空白）的词直接跳过，不进入练习列表。
    static func extractSentences(from words: [CachedWord]) -> [String] {
        words.compactMap { word in
            guard let data = word.examplesJSON.data(using: .utf8),
                  let examples = try? JSONDecoder().decode([Example].self, from: data),
                  let first = examples.first,
                  !first.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return first.en
        }
    }
}
