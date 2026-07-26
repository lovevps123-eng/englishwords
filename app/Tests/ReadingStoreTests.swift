// ReadingStoreTests.swift — 阅读模块：难度筛选 query 拼装、文章详情拉取、
// 点词收藏三种结果分支（collected/exists/404）。网络用自定义 URLProtocol mock（同 VocabStoreTests 套路）。
import XCTest
@testable import EnglishWords

private final class ReadingAPIMockProtocol: URLProtocol {
    static var lastRequestedPath: String?
    static var collectStatusCode = 200
    static var collectResponseBody = "{\"status\": \"collected\", \"word_id\": \"w1\"}"

    static func reset() {
        lastRequestedPath = nil
        collectStatusCode = 200
        collectResponseBody = "{\"status\": \"collected\", \"word_id\": \"w1\"}"
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = (request.url?.path ?? "") + "?" + (request.url?.query ?? "")
        ReadingAPIMockProtocol.lastRequestedPath = path

        if request.url?.path == "/api/vocab/collect" {
            respond(status: Self.collectStatusCode, body: Self.collectResponseBody)
            return
        }
        if request.url?.path == "/api/articles" {
            respond(status: 200, body: """
            {
              "items": [
                {"id": "1", "source": "bbc", "title": "T", "title_cn": null, "summary": null,
                 "difficulty": "intermediate", "category": "tech", "word_count": 10, "published_at": null}
              ],
              "total": 1, "page": 1, "pages": 1
            }
            """)
            return
        }
        if request.url?.path == "/api/articles/abc" {
            respond(status: 200, body: """
            {
              "id": "abc", "source": "bbc", "source_url": "https://x", "title": "T", "title_cn": null,
              "content": "P1.\\n\\nP2.", "content_cn": "中1。\\n\\n中2。", "summary": null,
              "vocabulary": null, "difficulty": "advanced", "category": "tech", "word_count": 20,
              "published_at": null
            }
            """)
            return
        }
        respond(status: 404, body: "{\"detail\": \"not found\"}")
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

final class ReadingStoreTests: XCTestCase {
    private var store: ReadingStore!

    override func setUp() {
        super.setUp()
        ReadingAPIMockProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReadingAPIMockProtocol.self]
        let apiClient = APIClient(session: URLSession(configuration: config), keychain: .shared)
        store = ReadingStore(apiClient: apiClient)
    }

    // ① 难度筛选为空（"全部"）不应带 difficulty query 参数。
    func testFetchArticlesWithoutDifficultyOmitsQueryParam() async throws {
        _ = try await store.fetchArticles(difficulty: "")
        XCTAssertFalse(ReadingAPIMockProtocol.lastRequestedPath?.contains("difficulty") ?? true)
    }

    // ② 指定难度应原样拼进 query（对应后端 difficulty: str | None query 参数名）。
    func testFetchArticlesWithDifficultyIncludesQueryParam() async throws {
        _ = try await store.fetchArticles(difficulty: "advanced")
        XCTAssertTrue(ReadingAPIMockProtocol.lastRequestedPath?.contains("difficulty=advanced") ?? false)
    }

    // ③ 详情接口解码 + 段落按 "\n\n" 切分。
    func testFetchArticleDetailDecodesAndSplitsParagraphs() async throws {
        let detail = try await store.fetchArticleDetail(id: "abc")
        XCTAssertEqual(detail.difficulty, "advanced")
        XCTAssertEqual(detail.content.components(separatedBy: "\n\n"), ["P1.", "P2."])
        XCTAssertEqual(detail.contentCn?.components(separatedBy: "\n\n"), ["中1。", "中2。"])
    }

    // ④ 收藏成功（新建）。
    func testCollectWordReturnsCollected() async {
        ReadingAPIMockProtocol.collectStatusCode = 200
        ReadingAPIMockProtocol.collectResponseBody = "{\"status\": \"collected\", \"word_id\": \"w1\"}"
        let outcome = await store.collectWord("apple")
        XCTAssertEqual(outcome, .collected)
    }

    // ⑤ 收藏重复（后端幂等返回 "exists"）。
    func testCollectWordReturnsAlreadyCollectedWhenStatusExists() async {
        ReadingAPIMockProtocol.collectStatusCode = 200
        ReadingAPIMockProtocol.collectResponseBody = "{\"status\": \"exists\", \"word_id\": \"w1\"}"
        let outcome = await store.collectWord("apple")
        XCTAssertEqual(outcome, .alreadyCollected)
    }

    // ⑥ 词典查无此词：后端 404，映射为 .notFound（UI 据此 toast "词典中没有这个词"）。
    func testCollectWordReturnsNotFoundOn404() async {
        ReadingAPIMockProtocol.collectStatusCode = 404
        ReadingAPIMockProtocol.collectResponseBody = "{\"detail\": \"词典中没有这个词\"}"
        let outcome = await store.collectWord("zzzznotaword")
        XCTAssertEqual(outcome, .notFound)
    }

    // ⑦ 其它服务端错误映射为 .failed，携带错误信息供 UI 展示。
    func testCollectWordReturnsFailedOnServerError() async {
        ReadingAPIMockProtocol.collectStatusCode = 500
        ReadingAPIMockProtocol.collectResponseBody = "{\"detail\": \"服务器内部错误\"}"
        let outcome = await store.collectWord("apple")
        guard case .failed(let message) = outcome else {
            return XCTFail("应返回 .failed，实际是 \(outcome)")
        }
        XCTAssertEqual(message, "服务器内部错误")
    }
}
