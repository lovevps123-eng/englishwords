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
struct Definition: Decodable, Equatable {
    let pos: String
    let meaning: String
    let example: String?
}

/// WordPayload.examples 单条例句：{en, cn, source}
/// source ∈ "gaokao" | "tatoeba" | "freedict" | "llm"
struct Example: Decodable, Equatable {
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
