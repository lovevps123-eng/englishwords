// WordDiff.swift — 词级对齐比对（LCS），App v1 将复用
import Foundation

func normalize(_ s: String) -> [String] {
    s.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
}

/// LCS 对齐：返回目标句每个词是否被读中
func wordDiff(target: String, recognized: String) -> [(word: String, hit: Bool)] {
    let t = normalize(target), r = normalize(recognized)
    var dp = Array(repeating: Array(repeating: 0, count: r.count + 1), count: t.count + 1)
    for i in stride(from: t.count - 1, through: 0, by: -1) {
        for j in stride(from: r.count - 1, through: 0, by: -1) {
            dp[i][j] = t[i] == r[j] ? dp[i+1][j+1] + 1 : max(dp[i+1][j], dp[i][j+1])
        }
    }
    var result: [(String, Bool)] = []
    var i = 0, j = 0
    while i < t.count {
        if j < r.count && t[i] == r[j] { result.append((t[i], true)); i += 1; j += 1 }
        else if j < r.count && dp[i][j+1] >= dp[i+1][j] { j += 1 }
        else { result.append((t[i], false)); i += 1 }
    }
    return result
}

func score(_ diff: [(word: String, hit: Bool)]) -> Int {
    diff.isEmpty ? 0 : Int(Double(diff.filter(\.hit).count) / Double(diff.count) * 100)
}
