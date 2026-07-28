// VocabStoreTests.swift — TDD：离线队列（submit 本地入队）+ 幂等同步（sync 成功清空/失败保留）+
// 队列覆盖写入（refreshQueue 不重复累积）。用 in-memory ModelContainer，网络用自定义 URLProtocol mock。
import XCTest
import SwiftData
@testable import EnglishWords

/// 拦截 /api/vocab/queue 与 /api/vocab/results：
/// - queue 固定返回 `queueResponseJSON`（测试按需覆盖）
/// - results 按 `resultsShouldFail` 决定返回 200 还是 500
private final class VocabAPIMockProtocol: URLProtocol {
    static var queueResponseJSON = "{\"new\": [], \"review\": []}"
    static var resultsShouldFail = false

    static func reset() {
        queueResponseJSON = "{\"new\": [], \"review\": []}"
        resultsShouldFail = false
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        switch path {
        case "/api/vocab/queue":
            respond(status: 200, body: Self.queueResponseJSON)
        case "/api/vocab/results":
            if Self.resultsShouldFail {
                respond(status: 500, body: "{\"detail\": \"boom\"}")
            } else {
                respond(status: 200, body: "{\"processed\": 1, \"skipped\": 0}")
            }
        default:
            respond(status: 404, body: "{\"detail\": \"not found\"}")
        }
    }

    override func stopLoading() {}

    private func respond(status: Int, body: String) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class VocabStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var apiClient: APIClient!

    override func setUpWithError() throws {
        try super.setUpWithError()
        VocabAPIMockProtocol.reset()

        let schema = Schema([CachedWord.self, PendingResult.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [VocabAPIMockProtocol.self]
        apiClient = APIClient(session: URLSession(configuration: sessionConfig), keychain: .shared)
    }

    // ① submit 生成 pending 行且 clientId 唯一，并把词标记已答；纯本地，不需要网络。
    func testSubmitGeneratesPendingRowWithUniqueClientId() throws {
        let store = VocabStore(modelContext: context, apiClient: apiClient)
        let word1 = CachedWord(
            serverId: "w1", word: "apple", phonetic: nil,
            definitionsJSON: "[]", examplesJSON: "[]", stage: 0, group: "new"
        )
        let word2 = CachedWord(
            serverId: "w2", word: "banana", phonetic: nil,
            definitionsJSON: "[]", examplesJSON: "[]", stage: 0, group: "new"
        )
        context.insert(word1)
        context.insert(word2)

        store.submit(feedback: .know, for: word1)
        store.submit(feedback: .fuzzy, for: word2)

        let pending = try context.fetch(FetchDescriptor<PendingResult>())
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(Set(pending.map(\.clientId)).count, 2, "clientId 应唯一")
        XCTAssertTrue(word1.answered)
        XCTAssertTrue(word2.answered)
        XCTAssertEqual(Set(pending.map(\.feedback)), ["know", "fuzzy"])
        XCTAssertEqual(Set(pending.map(\.wordId)), ["w1", "w2"])
    }

    // ② sync 失败时静默保留 pending（下次可重发）并返回 nil；成功后清空已提交行并返回
    // {processed, skipped}，供 UI 区分"已同步 N 条"与"同步失败，稍后自动重试"。
    func testSyncClearsPendingOnSuccessAndKeepsOnFailure() async throws {
        let store = VocabStore(modelContext: context, apiClient: apiClient)
        context.insert(PendingResult(clientId: UUID().uuidString, wordId: "w1", feedback: "know"))

        VocabAPIMockProtocol.resultsShouldFail = true
        let failResult = await store.sync()
        XCTAssertNil(failResult, "同步失败应返回 nil")
        var pending = try context.fetch(FetchDescriptor<PendingResult>())
        XCTAssertEqual(pending.count, 1, "同步失败应静默保留 pending 行")

        VocabAPIMockProtocol.resultsShouldFail = false
        let successResult = await store.sync()
        XCTAssertEqual(successResult?.processed, 1)
        XCTAssertEqual(successResult?.skipped, 0)
        pending = try context.fetch(FetchDescriptor<PendingResult>())
        XCTAssertTrue(pending.isEmpty, "同步成功后应清空已提交的 pending 行")
    }

    // ③ refreshQueue 覆盖旧缓存：重复调用不会累积重复的 CachedWord 行。
    func testRefreshQueueOverwritesOldCacheWithoutDuplicating() async throws {
        let store = VocabStore(modelContext: context, apiClient: apiClient)
        context.insert(CachedWord(
            serverId: "stale", word: "stale-word", phonetic: nil,
            definitionsJSON: "[]", examplesJSON: "[]", stage: 0, group: "new"
        ))

        VocabAPIMockProtocol.queueResponseJSON = """
        {
          "new": [
            {"id": "n1", "word": "apple", "phonetic": "/ˈæpl/", "definitions": [], "examples": [], "stage": 0}
          ],
          "review": [
            {"id": "r1", "word": "banana", "phonetic": null, "definitions": [], "examples": [], "stage": 3}
          ]
        }
        """

        try await store.refreshQueue(tier: 1, newLimit: 50)

        var words = try context.fetch(FetchDescriptor<CachedWord>())
        XCTAssertEqual(words.count, 2, "旧的 stale 缓存应被清空，只剩本次响应的两条")
        XCTAssertFalse(words.contains { $0.serverId == "stale" })
        XCTAssertEqual(Set(words.map(\.group)), ["new", "review"])

        // 重复调用同一响应，不应累积出重复行
        try await store.refreshQueue(tier: 1, newLimit: 50)
        words = try context.fetch(FetchDescriptor<CachedWord>())
        XCTAssertEqual(words.count, 2, "重复 refreshQueue 不应重复累积")
    }

    // ④ reconcile：submit 一个词但还没 sync（PendingResult 未同步）时，refreshQueue 覆盖缓存不应
    // 把这个词的 answered 状态冲回 false——否则用户会对同一词再答一次（产生第二条 clientId），
    // todayProgress 也会倒退。
    func testRefreshQueuePreservesAnsweredStateForUnsyncedPendingWord() async throws {
        let store = VocabStore(modelContext: context, apiClient: apiClient)
        let word = CachedWord(
            serverId: "w1", word: "apple", phonetic: nil,
            definitionsJSON: "[]", examplesJSON: "[]", stage: 0, group: "new"
        )
        context.insert(word)
        store.submit(feedback: .know, for: word)

        let progressBefore = store.todayProgress
        XCTAssertEqual(progressBefore.done, 1)
        XCTAssertEqual(progressBefore.total, 1)

        // 还没 sync，服务端不知道这个词已答，队列响应里同一 serverId 又出现了
        VocabAPIMockProtocol.queueResponseJSON = """
        {
          "new": [
            {"id": "w1", "word": "apple", "phonetic": null, "definitions": [], "examples": [], "stage": 0}
          ],
          "review": []
        }
        """

        try await store.refreshQueue(tier: 1, newLimit: 50)

        let words = try context.fetch(FetchDescriptor<CachedWord>())
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words.first?.serverId, "w1")
        XCTAssertTrue(words.first?.answered ?? false, "本地已答未同步的词，刷新队列后仍应是 answered")

        let progressAfter = store.todayProgress
        XCTAssertEqual(progressAfter.done, 1, "todayProgress 不应因 refreshQueue 而倒退")
        XCTAssertEqual(progressAfter.total, 1)

        let pending = try context.fetch(FetchDescriptor<PendingResult>())
        XCTAssertEqual(pending.count, 1, "refreshQueue 不应产生第二条 pending")
    }

    // ⑤ clearAllLocalData：主动登出路径应清空 CachedWord 与 PendingResult 两张表，
    // 防止换账号后新账号看到旧账号缓存词，或旧账号未同步结果被用新账号 token 提交。
    func testClearAllLocalDataEmptiesCachedWordsAndPendingResults() throws {
        let store = VocabStore(modelContext: context, apiClient: apiClient)
        let word = CachedWord(
            serverId: "w1", word: "apple", phonetic: nil,
            definitionsJSON: "[]", examplesJSON: "[]", stage: 0, group: "new"
        )
        context.insert(word)
        store.submit(feedback: .know, for: word)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedWord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingResult>()).count, 1)

        store.clearAllLocalData()

        XCTAssertTrue(try context.fetch(FetchDescriptor<CachedWord>()).isEmpty, "clearAllLocalData 后 CachedWord 应全空")
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingResult>()).isEmpty, "clearAllLocalData 后 PendingResult 应全空")
    }
}
