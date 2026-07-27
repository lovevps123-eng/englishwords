// ScoringStrategy.swift — 评分策略抽象：spike 结论出来之前先用 LCS 百分比（StrictScoring，
// 即 spike 里原来的裸 score 函数），SpeakingStore 只持有协议类型，后续换算法（比如接入
// 音素级评分/容错阈值）只需新增一个 ScoringStrategy 实现并替换 SpeakingStore 的默认值，
// 不用动调用方（SpeakingView）代码。
import Foundation

protocol ScoringStrategy {
    func score(diff: WordDiff.Result) -> Int
}

/// 默认实现：与 spike ContentView 里验证过的 score 函数完全一致的 LCS 命中率百分比。
struct StrictScoring: ScoringStrategy {
    func score(diff: WordDiff.Result) -> Int {
        diff.isEmpty ? 0 : Int(Double(diff.filter(\.hit).count) / Double(diff.count) * 100)
    }
}
