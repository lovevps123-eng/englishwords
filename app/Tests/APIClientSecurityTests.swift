import XCTest
@testable import EnglishWords

private final class RecordingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var requestBodies: [Data?] = []
    private static var failure: URLError?
    private static var responseStatus = 200
    private static var responseBody = "{}"

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return requests.count
    }

    static var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }

    static var lastRequestBody: Data? {
        lock.lock(); defer { lock.unlock() }
        return requestBodies.last ?? nil
    }

    static func reset(
        failure: URLError? = nil,
        responseStatus: Int = 200,
        responseBody: String = "{}"
    ) {
        lock.lock(); defer { lock.unlock() }
        requests = []
        requestBodies = []
        self.failure = failure
        self.responseStatus = responseStatus
        self.responseBody = responseBody
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
        Self.lock.lock()
        Self.requests.append(request)
        Self.requestBodies.append(body)
        let failure = Self.failure
        let responseStatus = Self.responseStatus
        let responseBody = Self.responseBody
        Self.lock.unlock()

        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }

        let response = HTTPURLResponse(
            url: request.url!, statusCode: responseStatus, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBodyStream(_ stream: InputStream?) -> Data? {
        guard let stream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

final class APIClientSecurityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var client: APIClient!
    private var keychain: KeychainStore!

    override func setUp() {
        super.setUp()
        suiteName = "APIClientSecurityTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("https://api.example.com", forKey: AppConfiguration.serverOverrideKey)

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [RecordingURLProtocol.self]
        let configuration = AppConfiguration(defaults: defaults, environment: .debug)
        keychain = KeychainStore(service: "APIClientSecurityTests.\(UUID().uuidString)")
        client = APIClient(
            session: URLSession(configuration: sessionConfiguration),
            keychain: keychain,
            configuration: configuration,
            appClientKey: "test-app-key"
        )
        RecordingURLProtocol.reset()
    }

    override func tearDown() {
        keychain.clear()
        keychain.clearDeletionReceipt()
        defaults.removePersistentDomain(forName: suiteName)
        client = nil
        keychain = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testValidAPIPathUsesConfiguredOrigin() async throws {
        _ = try await client.request("/api/vocab/queue")

        XCTAssertEqual(RecordingURLProtocol.lastRequest?.url?.absoluteString, "https://api.example.com/api/vocab/queue")
    }

    func testRootOverrideResolvesVocabQueueExactlyUnderConfiguredOrigin() async throws {
        try AppConfiguration(defaults: defaults, environment: .debug)
            .applyServerOverride("https://api.example.com///")

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

    func testRegistrationAndAccountSessionOmitAppClientHeader() async throws {
        _ = try await client.request("/api/auth/register", method: "POST", credential: .none)
        XCTAssertNil(RecordingURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-App-Client"))

        _ = try await client.request("/api/account/session", method: "POST", credential: .none)
        XCTAssertNil(RecordingURLProtocol.lastRequest?.value(forHTTPHeaderField: "X-App-Client"))
    }

    func testManagementCredentialUsesOnlyProvidedToken() async throws {
        XCTAssertTrue(keychain.saveTokens(access: "learning-access", refresh: "learning-refresh"))

        _ = try await client.request("/api/account/status", credential: .management("management-token"))

        XCTAssertEqual(
            RecordingURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer management-token"
        )
        XCTAssertEqual(RecordingURLProtocol.requestCount, 1)
    }

    func testManagementCredentialDoesNotRefreshOrClearLearningTokensAfter401() async {
        XCTAssertTrue(keychain.saveTokens(access: "learning-access", refresh: "learning-refresh"))
        RecordingURLProtocol.reset(
            responseStatus: 401,
            responseBody: #"{"detail":{"code":"ACCOUNT_MANAGEMENT_TOKEN_INVALID","message":"账号管理会话已过期"}}"#
        )

        do {
            _ = try await client.request("/api/account/status", credential: .management("expired-token"))
            XCTFail("Expected a server error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "ACCOUNT_MANAGEMENT_TOKEN_INVALID")
            XCTAssertEqual(error.errorDescription, "账号管理会话已过期")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }

        XCTAssertEqual(RecordingURLProtocol.requestCount, 1)
        XCTAssertEqual(keychain.loadTokens(), AuthTokens(access: "learning-access", refresh: "learning-refresh"))
    }

    func testReceiptStatusUsesJSONBodyWithoutAnyCredential() async throws {
        XCTAssertTrue(keychain.saveTokens(access: "learning-access", refresh: "learning-refresh"))
        RecordingURLProtocol.reset(responseBody: """
        {
          "status": "processing",
          "requested_at": "2026-09-06T01:02:03Z",
          "due_at": "2026-09-13T01:02:03Z",
          "completed_at": null,
          "cancelled_at": null,
          "failure_category": null
        }
        """)

        let _: ReceiptStatusResponse = try await client.post(
            "/api/account/deletion-receipt/status",
            body: DeletionReceiptStatusRequest(receipt: "receipt-secret"),
            credential: .none
        )

        let request = try XCTUnwrap(RecordingURLProtocol.lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-App-Client"))
        XCTAssertNil(request.url?.query)
        let body = try XCTUnwrap(RecordingURLProtocol.lastRequestBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["receipt": "receipt-secret"])
    }

    func testObjectErrorPreservesMachineCodeAndSafeMessage() async {
        RecordingURLProtocol.reset(
            responseStatus: 503,
            responseBody: #"{"detail":{"code":"ACCOUNT_DELETION_NOT_ENABLED","message":"功能未启用"}}"#
        )

        do {
            _ = try await client.request("/api/account/status", credential: .none)
            XCTFail("Expected a server error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "ACCOUNT_DELETION_NOT_ENABLED")
            XCTAssertEqual(error.errorDescription, "功能未启用")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testStringErrorDetailRemainsSupported() async {
        RecordingURLProtocol.reset(responseStatus: 400, responseBody: #"{"detail":"请求参数错误"}"#)

        do {
            _ = try await client.request("/api/account/status", credential: .none)
            XCTFail("Expected a server error")
        } catch let error as APIError {
            XCTAssertNil(error.code)
            XCTAssertEqual(error.errorDescription, "请求参数错误")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
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
