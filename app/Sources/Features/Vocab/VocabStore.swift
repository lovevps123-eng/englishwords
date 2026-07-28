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
    ///
    /// reconcile：未同步的 PendingResult 记着"本地已答但服务端还不知道"的词。如果无条件覆盖，
    /// 这些词在新队列里会以 answered=false 重新出现——todayProgress 倒退，且用户会对同一词
    /// 再答一次，产生第二条 clientId（SRS 被重复推进）。所以写入新集合时，serverId 命中
    /// 未同步 PendingResult.wordId 集合的词一律直接置 answered=true，不管服务端这次还给不给这词。
    func refreshQueue(tier: Int, newLimit: Int) async throws {
        let response: QueueResponse = try await apiClient.get(
            "/api/vocab/queue?new_limit=\(newLimit)&tier=\(tier)"
        )

        let unsyncedWordIds = Set(
            (try? modelContext.fetch(FetchDescriptor<PendingResult>()))?.map(\.wordId) ?? []
        )

        let existing = try modelContext.fetch(FetchDescriptor<CachedWord>())
        for word in existing {
            modelContext.delete(word)
        }

        for payload in response.new {
            modelContext.insert(try makeCachedWord(from: payload, group: "new", unsyncedWordIds: unsyncedWordIds))
        }
        for payload in response.review {
            modelContext.insert(try makeCachedWord(from: payload, group: "review", unsyncedWordIds: unsyncedWordIds))
        }

        try modelContext.save()
    }

    /// 本地生成幂等 clientId，立即入队并把词标记已答；不等待网络，UI 可即时响应。
    /// feedback 收紧为 Feedback 枚举（入口把关），避免脏字符串混进 PendingResult 批次。
    func submit(feedback: Feedback, for word: CachedWord) {
        let pending = PendingResult(
            clientId: UUID().uuidString, wordId: word.serverId, feedback: feedback.rawValue
        )
        modelContext.insert(pending)
        word.answered = true
        try? modelContext.save()
    }

    /// 批量补交所有待同步结果。成功才删除已提交行，返回服务端 `{processed, skipped}`；
    /// 失败（网络/服务端错误）静默保留 pending、返回 nil——下次调用自然重试，client_id 幂等
    /// 保证重发安全。返回值供 UI 区分"已同步 N 条"与"同步失败，稍后自动重试"（nil = 失败）。
    @discardableResult
    func sync() async -> (processed: Int, skipped: Int)? {
        guard let pending = try? modelContext.fetch(FetchDescriptor<PendingResult>()), !pending.isEmpty else {
            return (processed: 0, skipped: 0)
        }

        let items = pending.map {
            VocabResultItem(clientId: $0.clientId, wordId: $0.wordId, feedback: $0.feedback)
        }

        do {
            let response: SubmitResultsResponse = try await apiClient.post(
                "/api/vocab/results", body: SubmitResultsRequest(results: items)
            )
            for item in pending {
                modelContext.delete(item)
            }
            try? modelContext.save()
            return (processed: response.processed, skipped: response.skipped)
        } catch {
            // 静默保留：不清空 pending，下次 sync() 会带着相同 clientId 重发（幂等安全）。
            return nil
        }
    }

    /// 清空全部本地词库缓存与待同步队列（CachedWord + PendingResult）。
    ///
    /// 仅应在**用户主动登出**路径调用（SettingsView 登出确认回调），而不是 401 强制登出
    /// （authDidLogout 通知）路径：401 只是同一账号的 token 过期，未同步的 PendingResult
    /// 要留着，等用户重新登录后 sync() 补交；但如果换了账号（主动登出后另一人登录），
    /// A 账号的 PendingResult 会带着 B 账号的新 token 提交，污染 B 的服务端 SRS 数据——
    /// 这是不可逆操作，所以主动登出必须在 authStore.logout() 之前把两张表清空。
    func clearAllLocalData() {
        let words = (try? modelContext.fetch(FetchDescriptor<CachedWord>())) ?? []
        for word in words {
            modelContext.delete(word)
        }
        let pending = (try? modelContext.fetch(FetchDescriptor<PendingResult>())) ?? []
        for item in pending {
            modelContext.delete(item)
        }
        try? modelContext.save()
    }

    /// 今日进度 = 当前缓存队列（refreshQueue 覆盖式写入，天然对应"今日"队列）中已作答 / 总数
    var todayProgress: (done: Int, total: Int) {
        let all = (try? modelContext.fetch(FetchDescriptor<CachedWord>())) ?? []
        let done = all.filter(\.answered).count
        return (done, all.count)
    }

    private func makeCachedWord(
        from payload: WordPayload, group: String, unsyncedWordIds: Set<String>
    ) throws -> CachedWord {
        let definitionsData = try JSONEncoder().encode(payload.definitions)
        let examplesData = try JSONEncoder().encode(payload.examples)
        return CachedWord(
            serverId: payload.id,
            word: payload.word,
            phonetic: payload.phonetic,
            definitionsJSON: String(data: definitionsData, encoding: .utf8) ?? "[]",
            examplesJSON: String(data: examplesData, encoding: .utf8) ?? "[]",
            stage: payload.stage,
            group: group,
            answered: unsyncedWordIds.contains(payload.id)
        )
    }
}
