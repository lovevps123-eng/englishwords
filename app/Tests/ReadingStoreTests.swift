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

    // 首版不能再把后端抓取列表展示出来，也不应在本地内容失败时退回该接口。
    func testFetchArticlesUsesBundledOriginalsWithoutArticleRequest() async throws {
        let response = try await store.fetchArticles(difficulty: "")
        XCTAssertEqual(response.total, 6)
        XCTAssertEqual(response.items.first?.id, "original-small-notebook")
        XCTAssertTrue(response.items.allSatisfy { $0.source == "AI 辅助创作" })
        XCTAssertNil(ReadingAPIMockProtocol.lastRequestedPath)
    }

    func testFetchArticlesFiltersBeforePagination() async throws {
        let response = try await store.fetchArticles(difficulty: "advanced", page: 2, perPage: 2)
        XCTAssertEqual(response.total, 3)
        XCTAssertEqual(response.pages, 2)
        XCTAssertEqual(response.page, 2)
        XCTAssertEqual(response.items.map(\.id), ["original-library-map"])
        XCTAssertNil(ReadingAPIMockProtocol.lastRequestedPath)
    }

    func testEveryListedArticleHasAlignedBilingualDetail() async throws {
        let response = try await store.fetchArticles(difficulty: nil)
        XCTAssertEqual(response.items.count, 6)
        XCTAssertEqual(Set(response.items.map(\.id)).count, 6)
        for item in response.items {
            let detail = try await store.fetchArticleDetail(id: item.id)
            XCTAssertEqual(detail.id, item.id)
            XCTAssertEqual(detail.title, item.title)
            XCTAssertTrue(detail.sourceUrl.isEmpty)
            let english = detail.content.components(separatedBy: "\n\n")
            let chinese = try XCTUnwrap(detail.contentCn).components(separatedBy: "\n\n")
            XCTAssertEqual(english.count, 3)
            XCTAssertEqual(chinese.count, english.count)
            XCTAssertTrue(chinese.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            XCTAssertEqual(detail.wordCount, detail.content.split(whereSeparator: \.isWhitespace).count)
            XCTAssertGreaterThanOrEqual(detail.wordCount, 100)
        }
        XCTAssertNil(ReadingAPIMockProtocol.lastRequestedPath)
    }

    func testUnknownArticleDoesNotFallBackToScrapedDetail() async {
        do {
            _ = try await store.fetchArticleDetail(id: "abc")
            XCTFail("不应加载后端抓取的文章")
        } catch {
            XCTAssertNil(ReadingAPIMockProtocol.lastRequestedPath)
        }
    }

    func testOutOfRangePageReturnsEmptyList() async throws {
        let response = try await store.fetchArticles(difficulty: nil, page: 20, perPage: 2)
        XCTAssertTrue(response.items.isEmpty)
        XCTAssertEqual(response.total, 6)
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
