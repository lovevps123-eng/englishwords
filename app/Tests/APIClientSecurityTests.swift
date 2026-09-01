import XCTest
@testable import EnglishWords

private final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var failure: URLError?

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    static var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }

    static func reset(failure: URLError? = nil) {
        lock.lock(); defer { lock.unlock() }
        requests = []
        self.failure = failure
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let failure = Self.failure
        Self.lock.unlock()

        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class APIClientSecurityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        suiteName = "APIClientSecurityTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("https://api.example.com", forKey: AppConfiguration.serverOverrideKey)

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RecordingURLProtocol.self]
        let configuration = AppConfiguration(defaults: defaults, environment: .debug)
        client = APIClient(
            session: URLSession(configuration: sessionConfiguration),
            keychain: .shared,
            configuration: configuration,
            appClientKey: "test-app-key"
        )
        RecordingURLProtocol.reset()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        client = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testValidAPIPathUsesConfiguredOrigin() async throws {
        _ = try await client.request("/api/vocab/queue")

        XCTAssertEqual(RecordingURLProtocol.lastRequest?.url?.absoluteString, "https://api.example.com/api/vocab/queue")
    }

    func testAbsoluteURLIsRejected() async {
        await assertInvalidURL(for: "https://attacker.example/api/vocab/queue")
    }

    func testNonAPIPathIsRejected() async {
        await assertInvalidURL(for: "/vocab/queue")
    }

    func testNormalizedPathCannotEscapeAPIRoot() async {
        await assertInvalidURL(for: "/api/../private")
    }

    func testLoginAloneIncludesAppClientHeader() async throws {
        _ = try await client.request("/api/auth/login", method: "POST", authorized: false)

        XCTAssertEqual(RecordingURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-App-Client"), "test-app-key")
    }

    func testVocabAndRefreshRequestsOmitAppClientHeader() async throws {
        _ = try await client.request("/api/vocab/queue")
        XCTAssertNil(RecordingURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-App-Client"))

        _ = try await client.request("/api/auth/refresh", method: "POST", authorized: false)
        XCTAssertNil(RecordingURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-App-Client"))
    }

    func testNetworkUnavailableErrorIsMapped() async {
        RecordingURLProtocol.reset(failure: URLError(.notConnectedToInternet))
        await assertMappedError(.networkUnavailable, message: "网络不可用，请检查网络后重试")
    }

    func testTimeoutErrorIsMapped() async {
        RecordingURLProtocol.reset(failure: URLError(.timedOut))
        await assertMappedError(.timeout, message: "服务器响应超时，请稍后重试")
    }

    func testSecureConnectionErrorIsMapped() async {
        RecordingURLProtocol.reset(failure: URLError(.secureConnectionFailed))
        await assertMappedError(.secureConnectionFailed, message: "无法与服务器建立安全连接")
    }

    func testDefaultSessionUsesReleaseTimeoutPolicy() {
        let session = APIClient.makeDefaultSession()
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 30)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 60)
    }

    private func assertInvalidURL(for path: String) async {
        do {
            _ = try await client.request(path)
            XCTFail("Expected invalid URL for \(path)")
        } catch let error as APIError {
            guard case .invalidURL = error else {
                return XCTFail("Expected invalid URL, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError.invalidURL, got \(error)")
        }
        XCTAssertEqual(RecordingURLProtocol.requestCount, 0)
    }

    private func assertMappedError(_ expected: APIError, message: String) async {
        do {
            _ = try await client.request("/api/vocab/queue")
            XCTFail("Expected transport error")
        } catch let error as APIError {
            switch (expected, error) {
            case (.networkUnavailable, .networkUnavailable),
                 (.timeout, .timeout),
                 (.secureConnectionFailed, .secureConnectionFailed):
                XCTAssertEqual(error.errorDescription, message)
            default:
                XCTFail("Unexpected API error \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }
}
