// WordDiff.swift — 词级对齐比对（LCS）。从 spike/Sources/WordDiff.swift 逐字复制而来
// （spike 目录本身不动，见 task-7-report.md 复制处理说明），仅做了一处调整：
// spike 版本是三个裸的全局函数（normalize/wordDiff/score），直接拷进 App 模块会和其他
// Feature 目录（未来可能出现同名 normalize/score 工具函数）产生全局命名冲突；这里收进
// enum WordDiff 命名空间，调用处相应改成 WordDiff.diff(...)。
// 另外 score 函数已被 ScoringStrategy.swift 里的 StrictScoring 取代（同一段 LCS 百分比逻辑，
// 只是从自由函数变成协议实现，方便 spike 结论出来后整体换算法），这里不再保留。
import Foundation

enum WordDiff {
    /// 目标句每个词是否被读中的判定结果。
    typealias Result = [(word: String, hit: Bool)]

    static func normalize(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// LCS 对齐：返回目标句每个词是否被读中
    static func diff(target: String, recognized: String) -> Result {
        let t = normalize(target), r = normalize(recognized)
        var dp = Array(repeating: Array(repeating: 0, count: r.count + 1), count: t.count + 1)
        for i in stride(from: t.count - 1, through: 0, by: -1) {
            for j in stride(from: r.count - 1, through: 0, by: -1) {
                dp[i][j] = t[i] == r[j] ? dp[i+1][j+1] + 1 : max(dp[i+1][j], dp[i][j+1])
            }
        }
        var result: Result = []
        var i = 0, j = 0
        while i < t.count {
            if j < r.count && t[i] == r[j] { result.append((t[i], true)); i += 1; j += 1 }
            else if j < r.count && dp[i][j+1] >= dp[i+1][j] { j += 1 }
            else { result.append((t[i], false)); i += 1 }
        }
        return result
    }
}
