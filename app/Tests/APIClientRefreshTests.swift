// APIClientRefreshTests.swift — 验证并发 401 只触发一次 /api/auth/refresh（single-flight 去重）
import XCTest
@testable import EnglishWords

/// 拦截所有请求：
/// - /api/auth/refresh：计数 + 人为延迟（放大并发窗口），返回新 token 对
/// - 其它受保护路径：Authorization 带旧 token 时返回 401，带新 token 时返回 200
final class RefreshCountingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var _refreshCallCount = 0

    static var refreshCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _refreshCallCount
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _refreshCallCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""

        if path == "/api/auth/refresh" {
            RefreshCountingURLProtocol.lock.lock()
            RefreshCountingURLProtocol._refreshCallCount += 1
            RefreshCountingURLProtocol.lock.unlock()

            // 放大竞态窗口：让两个并发调用者都有机会各自看到 401 并尝试发起 refresh。
            Thread.sleep(forTimeInterval: 0.1)

            let json = """
            {"access_token": "new-access-token", "refresh_token": "new-refresh-token", "token_type": "bearer"}
            """
            respond(status: 200, body: json)
            return
        }

        let auth = request.value(forHTTPHeaderField: "Authorization")
        if auth == "Bearer new-access-token" {
            respond(status: 200, body: "{}")
        } else {
            respond(status: 401, body: "{\"detail\": \"unauthorized\"}")
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

final class APIClientRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RefreshCountingURLProtocol.reset()
        KeychainStore.shared.saveTokens(access: "old-access-token", refresh: "old-refresh-token")
    }

    override func tearDown() {
        KeychainStore.shared.clear()
        super.tearDown()
    }

    func testConcurrent401sTriggerOnlyOneRefreshCall() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RefreshCountingURLProtocol.self]
        let session = URLSession(configuration: config)
        let client = APIClient(session: session, keychain: .shared)

        async let first: Data? = try? client.request("/api/study/queue")
        async let second: Data? = try? client.request("/api/word/list")
        async let third: Data? = try? client.request("/api/study/stats")

        let results = await [first, second, third]

        // 三路并发 401 都应最终通过（用新 token 重试成功），但只应有一次真正的 refresh 网络调用。
        XCTAssertTrue(results.allSatisfy { $0 != nil })
        XCTAssertEqual(RefreshCountingURLProtocol.refreshCallCount, 1)
    }
}
