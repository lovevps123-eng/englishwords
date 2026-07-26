// VocabStore.swift — 单词模块核心：离线队列缓存 + 幂等同步
// 设计取舍见 docs/specs/2026-07-25-english-app-refocus-design.md「错误处理」：
// 单词模块全离线可用（预取 + 补交）；submit() 纯本地不等网络，sync() 失败静默保留待下次重试。
import Foundation
import SwiftData

@Observable
final class VocabStore {
    private let modelContext: ModelContext
    private let apiClient: APIClient

    init(modelContext: ModelContext, apiClient: APIClient = .shared) {
        self.modelContext = modelContext
        self.apiClient = apiClient
    }

    /// 拉取当日队列并**覆盖**本地缓存：先清空旧 CachedWord 再插入新集合，
    /// 避免重复调用累积重复行。不影响 PendingResult（不同表，尚未同步的答题结果不会被清掉）。
    func refreshQueue(tier: Int, newLimit: Int) async throws {
        let response: QueueResponse = try await apiClient.get(
            "/api/vocab/queue?new_limit=\(newLimit)&tier=\(tier)"
        )

        let existing = try modelContext.fetch(FetchDescriptor<CachedWord>())
        for word in existing {
            modelContext.delete(word)
        }

        for payload in response.new {
            modelContext.insert(try makeCachedWord(from: payload, group: "new"))
        }
        for payload in response.review {
            modelContext.insert(try makeCachedWord(from: payload, group: "review"))
        }

        try modelContext.save()
    }

    /// 本地生成幂等 clientId，立即入队并把词标记已答；不等待网络，UI 可即时响应。
    func submit(feedback: String, for word: CachedWord) {
        let pending = PendingResult(clientId: UUID().uuidString, wordId: word.serverId, feedback: feedback)
        modelContext.insert(pending)
        word.answered = true
        try? modelContext.save()
    }

    /// 批量补交所有待同步结果。成功才删除已提交行；失败（网络/服务端错误）静默保留，
    /// 不抛出——下次调用自然重试，client_id 幂等保证重发安全。
    func sync() async {
        guard let pending = try? modelContext.fetch(FetchDescriptor<PendingResult>()), !pending.isEmpty else {
            return
        }

        let items = pending.map {
            VocabResultItem(clientId: $0.clientId, wordId: $0.wordId, feedback: $0.feedback)
        }

        do {
            let _: SubmitResultsResponse = try await apiClient.post(
                "/api/vocab/results", body: SubmitResultsRequest(results: items)
            )
            for item in pending {
                modelContext.delete(item)
            }
            try? modelContext.save()
        } catch {
            // 静默保留：不清空 pending，下次 sync() 会带着相同 clientId 重发（幂等安全）。
        }
    }

    /// 今日进度 = 当前缓存队列（refreshQueue 覆盖式写入，天然对应"今日"队列）中已作答 / 总数
    var todayProgress: (done: Int, total: Int) {
        let all = (try? modelContext.fetch(FetchDescriptor<CachedWord>())) ?? []
        let done = all.filter(\.answered).count
        return (done, all.count)
    }

    private func makeCachedWord(from payload: WordPayload, group: String) throws -> CachedWord {
        let definitionsData = try JSONEncoder().encode(payload.definitions)
        let examplesData = try JSONEncoder().encode(payload.examples)
        return CachedWord(
            serverId: payload.id,
            word: payload.word,
            phonetic: payload.phonetic,
            definitionsJSON: String(data: definitionsData, encoding: .utf8) ?? "[]",
            examplesJSON: String(data: examplesData, encoding: .utf8) ?? "[]",
            stage: payload.stage,
            group: group
        )
    }
}
