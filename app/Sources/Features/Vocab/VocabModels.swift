// VocabModels.swift — 单词模块本地缓存：@Model 版 CachedWord（服务端队列快照）与
// PendingResult（离线答题结果队列，同步核心）
import Foundation
import SwiftData

/// GET /api/vocab/queue 响应的本地快照。definitions/examples 以 DTO 序列化后的 JSON 字符串存储
/// （而非直接存 [Definition]/[Example] 结构体数组），需要展示时按需 JSONDecoder 解码。
@Model
final class CachedWord {
    var serverId: String
    var word: String
    var phonetic: String?
    var definitionsJSON: String
    var examplesJSON: String
    var stage: Int
    /// "new" | "review"，对应 QueueResponse 的分组，驱动 UI 区分新词/复习
    var group: String
    var answered: Bool

    init(
        serverId: String,
        word: String,
        phonetic: String?,
        definitionsJSON: String,
        examplesJSON: String,
        stage: Int,
        group: String,
        answered: Bool = false
    ) {
        self.serverId = serverId
        self.word = word
        self.phonetic = phonetic
        self.definitionsJSON = definitionsJSON
        self.examplesJSON = examplesJSON
        self.stage = stage
        self.group = group
        self.answered = answered
    }
}

/// 离线补交队列：submit() 立即本地写入一行，sync() 成功后按行删除。
/// clientId 唯一（App 端生成的 UUID）：后端 /api/vocab/results 以 client_id 为幂等主键去重，
/// 重发同一批不会重复计入进度。
@Model
final class PendingResult {
    @Attribute(.unique) var clientId: String
    var wordId: String
    /// "know" | "fuzzy" | "unknown"（后端契约常量，不得改名）
    var feedback: String
    var createdAt: Date

    init(clientId: String, wordId: String, feedback: String, createdAt: Date = Date()) {
        self.clientId = clientId
        self.wordId = wordId
        self.feedback = feedback
        self.createdAt = createdAt
    }
}
