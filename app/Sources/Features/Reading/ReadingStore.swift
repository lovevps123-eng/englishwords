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

/// 真实抓取文章经 html.unescape 还原后普遍使用 Unicode 弯引号（左单引号 U+2018、右单引号 U+2019），
/// 而不是 ASCII 直引号——"don't" 里的撇号实际是 U+2019。normalize 前先把这两个弯单引号统一映射成
/// 直引号 "'"，否则 filter 只认 ASCII "'"，会把 "don't" 分词成 "dont"，导致词典查询误 404。
/// 弯双引号（U+201C/U+201D）本身不该出现在 normalized 里，不需要映射——filter 的 isLetter/'/- 判断
/// 已经会把它们当标点丢弃。
private func normalizingCurlyQuotes(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{2018}", with: "'")
        .replacingOccurrences(of: "\u{2019}", with: "'")
}

/// 英文段落按空白切词，供阅读详情页渲染可点词 token（TappableParagraph 消费）。
func tokenizeArticleParagraph(_ text: String) -> [ArticleWordToken] {
    let rawTokens = text.split(whereSeparator: { $0.isWhitespace })
    return rawTokens.enumerated().map { index, token in
        let lowercasedQuoteNormalized = normalizingCurlyQuotes(token.lowercased())
        let normalized = lowercasedQuoteNormalized.filter { $0.isLetter || $0 == "'" || $0 == "-" }
        return ArticleWordToken(id: index, display: String(token), normalized: normalized)
    }
}
