// ReadingStore.swift — 外刊阅读模块：文章列表/详情拉取 + 阅读页点词收藏。
// 无本地持久化需求（不同于 VocabStore 的离线队列）：文章列表/详情是纯网络请求的薄封装，
// View 层自行持有 @State 结果；这里只做 APIClient 调用与结果归类。
import Foundation

@Observable
final class ReadingStore {
    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    /// difficulty 传 nil 或空串等价于"全部"（不带该 query 参数，对应后端 difficulty: str | None = None）。
    func fetchArticles(difficulty: String?, page: Int = 1, perPage: Int = 20) async throws -> ArticleListResponse {
        var path = "/api/articles?page=\(page)&per_page=\(perPage)"
        if let difficulty, !difficulty.isEmpty {
            path += "&difficulty=\(difficulty)"
        }
        return try await apiClient.get(path)
    }

    func fetchArticleDetail(id: String) async throws -> ArticleDetail {
        try await apiClient.get("/api/articles/\(id)")
    }

    enum CollectOutcome: Equatable {
        case collected
        case alreadyCollected
        case notFound
        case failed(String)
    }

    /// POST /api/vocab/collect。404（词典没有这个词）固定按 brief 约定的文案提示，不依赖后端
    /// HTTPException 的 message 原文——避免后端调整错误文案措辞后 UI 提示跟着漂移。
    func collectWord(_ word: String) async -> CollectOutcome {
        do {
            let response: CollectWordResponse = try await apiClient.post(
                "/api/vocab/collect", body: CollectWordRequest(word: word)
            )
            return response.status == "exists" ? .alreadyCollected : .collected
        } catch let error as APIError {
            if case .server(let status, _) = error, status == 404 {
                return .notFound
            }
            return .failed(error.errorDescription ?? "收藏失败")
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// 阅读详情页里一个可点的词 token。
/// - display：保留原始大小写与内部标点（如 "don't"），用于展示；
/// - normalized：去除首尾标点、转小写，作为 /api/vocab/collect 的 word 参数
///   （后端按 `lower(word)` 精确匹配 dictionary_entries，见 vocab.py collect_word()）。
/// 标点独占整个 token（如单独的 "—"）时 normalized 为空串，调用方应跳过收藏动作。
struct ArticleWordToken: Identifiable, Hashable {
    let id: Int
    let display: String
    let normalized: String
}

/// 引号类字符（直引号 + 弯引号，单/双）。用于区分"整词被引号包裹"（定界符，应剥离）与
/// "词内撇号"（如 don't，应保留并归一为直引号）——单纯"把弯引号全部替换成直引号再塞进白名单"
/// 会把 'historic'（英式媒体常见的引述写法）误留成 "'historic'"，见 task-6-report.md 记录的回归。
private let quoteCharacters: Set<Character> = ["'", "\"", "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}"]
private let straightApostropheQuoteCharacters: Set<Character> = ["'", "\u{2018}", "\u{2019}"]

/// 单个 token 的 normalize 分两步：
/// ① 先找到 token 里第一个字母与最后一个字母的位置，这个范围之外的所有引号/标点一律当定界符丢弃
///    （不管是直引号还是弯引号）——解决"整词被引号包裹"场景，如 'historic'. → historic；
/// ② 只对落在字母范围**内部**的单引号形态字符（直/弯）归一为直撇号并保留——解决"词内撇号"场景，
///    如 Don't（弯撇号）→ don't。词内双引号极罕见，按噪声丢弃。
/// 取舍：像 rock 'n' roll 里的 'n'，两侧引号都落在唯一字母 "n" 之外，会被①当定界符丢弃，
/// normalized 结果是 "n" 而非 "'n'"——与"整词被引号包裹"是同一模式，两者用同一条规则，
/// 优先保证"整词引述"场景正确（已在 task-6-report.md 说明这一取舍）。
private func normalizeToken(_ token: Substring) -> String {
    let chars = Array(token.lowercased())
    guard let firstLetterIndex = chars.firstIndex(where: { $0.isLetter }),
          let lastLetterIndex = chars.lastIndex(where: { $0.isLetter }) else {
        return ""
    }

    var result = ""
    for i in chars.indices {
        guard i >= firstLetterIndex, i <= lastLetterIndex else { continue }
        let c = chars[i]
        if quoteCharacters.contains(c) {
            if straightApostropheQuoteCharacters.contains(c) {
                result.append("'")
            }
            continue
        }
        if c.isLetter || c == "-" {
            result.append(c)
        }
    }
    return result
}

/// 英文段落按空白切词，供阅读详情页渲染可点词 token（TappableParagraph 消费）。
func tokenizeArticleParagraph(_ text: String) -> [ArticleWordToken] {
    let rawTokens = text.split(whereSeparator: { $0.isWhitespace })
    return rawTokens.enumerated().map { index, token in
        ArticleWordToken(id: index, display: String(token), normalized: normalizeToken(token))
    }
}
