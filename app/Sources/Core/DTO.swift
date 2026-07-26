// DTO.swift — 与后端 API 契约逐字段对应的请求/响应模型
// 契约来源：docs/specs/2026-07-25-english-app-refocus-design.md「API 契约」节，
// 并对照 senior-platform 后端源码核实字段名与可空性（见 task-2-report.md）。
import Foundation

// MARK: - Auth

/// POST /api/auth/login 请求体。turnstile_token 目前恒为 nil（App 无 Turnstile 挑战流程，
/// 见 task-2-report.md concerns：生产环境已配置 TURNSTILE_SECRET_KEY，登录会被拒绝）。
struct LoginRequest: Encodable {
    let phone: String
    let password: String
    var turnstileToken: String? = nil

    enum CodingKeys: String, CodingKey {
        case phone
        case password
        case turnstileToken = "turnstile_token"
    }
}

/// POST /api/auth/refresh 请求体
struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

/// POST /api/auth/login、POST /api/auth/refresh 的响应体
struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
    }
}

// MARK: - Vocab

/// WordPayload.definitions 单条释义：{pos, meaning, example}
/// example 后端可能为 null（Free Dictionary API 未提供例句时）
struct Definition: Codable, Equatable {
    let pos: String
    let meaning: String
    let example: String?
}

/// WordPayload.examples 单条例句：{en, cn, source}
/// source ∈ "gaokao" | "tatoeba" | "freedict" | "llm"
struct Example: Codable, Equatable {
    let en: String
    let cn: String
    let source: String
}

/// GET /api/vocab/queue 中单个词条的负载
struct WordPayload: Decodable, Equatable {
    let id: String
    let word: String
    let phonetic: String?
    let definitions: [Definition]
    let examples: [Example]
    let stage: Int
}

/// GET /api/vocab/queue 响应体
struct QueueResponse: Decodable {
    let new: [WordPayload]
    let review: [WordPayload]
}

/// POST /api/vocab/results 单条结果。feedback ∈ "know" | "fuzzy" | "unknown"（后端契约常量，不得改名）
struct VocabResultItem: Encodable {
    let clientId: String
    let wordId: String
    let feedback: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case wordId = "word_id"
        case feedback
    }
}

/// POST /api/vocab/results 请求体
struct SubmitResultsRequest: Encodable {
    let results: [VocabResultItem]
}

/// POST /api/vocab/results 响应体：重复 client_id 计入 skipped（离线补交幂等，重放安全）
struct SubmitResultsResponse: Decodable {
    let processed: Int
    let skipped: Int
}

/// GET /api/vocab/study-stats 响应体
struct StudyStats: Decodable {
    let learning: Int
    let mastered: Int
    let dueToday: Int
    let daysActive: Int
    let streak: Int

    enum CodingKeys: String, CodingKey {
        case learning
        case mastered
        case dueToday = "due_today"
        case daysActive = "days_active"
        case streak
    }
}

/// POST /api/vocab/collect 请求体（阅读页点词收藏）
struct CollectWordRequest: Encodable {
    let word: String
}

/// POST /api/vocab/collect 响应体。status ∈ "collected"（新建）| "exists"（已收藏过，接口幂等）；
/// 词典查无此词时后端返回 404（HTTPException），走 APIError.server 分支，不会解码到这个类型。
struct CollectWordResponse: Decodable {
    let status: String
    let wordId: String

    enum CodingKeys: String, CodingKey {
        case status
        case wordId = "word_id"
    }
}

// MARK: - Reading
// 契约核对：backend/app/api/articles.py list_articles()/get_article() 的返回字典（非直接对应
// backend/app/models/article.py 的 EnglishArticle ORM 全字段——content/content_cn/vocabulary
// 仅详情接口才返回，列表接口不带）。difficulty 实际取值见 article_fetcher.py:218/227：
// "beginner"/"intermediate"/"advanced"（非 model 注释里旧版 "mixed" 三档说法）。

/// GET /api/articles 列表项
struct ArticleSummary: Decodable, Identifiable, Hashable {
    let id: String
    let source: String
    let title: String
    let titleCn: String?
    let summary: String?
    let difficulty: String
    let category: String
    let wordCount: Int
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, source, title
        case titleCn = "title_cn"
        case summary, difficulty, category
        case wordCount = "word_count"
        case publishedAt = "published_at"
    }
}

/// GET /api/articles 响应体：{"items", "total", "page", "pages"}
struct ArticleListResponse: Decodable {
    let items: [ArticleSummary]
    let total: Int
    let page: Int
    let pages: Int
}

/// EnglishArticle.vocabulary（JSON 列）单条词汇，字段来自 article_fetcher.py 里 LLM 的输出 schema
/// （见 _translate_article prompt "vocabulary" 结构）。这是 LLM 自由生成的辅助字段，非强 schema，
/// 除 word 外全部可空；即便某条目形状与预期不符，ArticleDetail 的自定义解码也会把整个数组兜底为 nil，
/// 不让详情页因这个辅助字段解码失败而整体打不开。
struct ArticleVocabularyItem: Decodable, Hashable {
    let word: String
    let phonetic: String?
    let meaning: String?
    let examples: [String]?
    let synonyms: String?
    let note: String?
}

/// GET /api/articles/{id} 响应体。content/content_cn 是整篇 "\n\n" 拼接的纯文本
/// （已核对 article_fetcher.py:308-310 保存逻辑：`"\n\n".join(paragraphs)`，
/// 不是分段 JSON 数组），前端按 "\n\n" split 还原段落，按下标对应中英文。
struct ArticleDetail: Decodable {
    let id: String
    let source: String
    let sourceUrl: String
    let title: String
    let titleCn: String?
    let content: String
    let contentCn: String?
    let summary: String?
    let vocabulary: [ArticleVocabularyItem]?
    let difficulty: String
    let category: String
    let wordCount: Int
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, source
        case sourceUrl = "source_url"
        case title
        case titleCn = "title_cn"
        case content
        case contentCn = "content_cn"
        case summary, vocabulary, difficulty, category
        case wordCount = "word_count"
        case publishedAt = "published_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        source = try container.decode(String.self, forKey: .source)
        sourceUrl = try container.decode(String.self, forKey: .sourceUrl)
        title = try container.decode(String.self, forKey: .title)
        titleCn = try container.decodeIfPresent(String.self, forKey: .titleCn)
        content = try container.decode(String.self, forKey: .content)
        contentCn = try container.decodeIfPresent(String.self, forKey: .contentCn)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        // vocabulary 是 LLM 自由格式输出：解码失败（某条目缺字段/类型不符）时兜底为 nil，
        // 不让这个辅助字段拖垮整个 ArticleDetail 的解码。
        vocabulary = (try? container.decodeIfPresent([ArticleVocabularyItem].self, forKey: .vocabulary)) ?? nil
        difficulty = try container.decode(String.self, forKey: .difficulty)
        category = try container.decode(String.self, forKey: .category)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
    }
}
