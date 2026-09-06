// APIClient.swift — 网络层：base URL 解析、JWT 附带、401 自动 refresh 重试一次
import Foundation

extension Notification.Name {
    /// refresh 也失败时广播，AuthStore 监听后登出回登录页
    static let authDidLogout = Notification.Name("APIClient.authDidLogout")
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case server(status: Int, code: String?, message: String)
    case unauthorized
    case decoding(Error)
    case networkUnavailable
    case timeout
    case secureConnectionFailed
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效"
        case .invalidResponse:
            return "服务器响应异常"
        case .server(_, _, let message):
            return message
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .decoding:
            return "数据解析失败"
        case .networkUnavailable:
            return "网络不可用，请检查网络后重试"
        case .timeout:
            return "服务器响应超时，请稍后重试"
        case .secureConnectionFailed:
            return "无法与服务器建立安全连接"
        case .transport:
            return "网络请求失败，请稍后重试"
        }
    }

    var code: String? {
        guard case .server(_, let code, _) = self else { return nil }
        return code
    }
}

enum RequestCredential {
    case none
    case learning
    case management(String)
}

/// 后端 FastAPI HTTPException 同时存在字符串和结构化 detail 两种形式。
private struct ErrorEnvelope: Decodable {
    let detail: Detail?

    enum Detail: Decodable {
        case text(String)
        case object(code: String?, message: String?)

        private enum CodingKeys: String, CodingKey {
            case code
            case message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            let object = try decoder.container(keyedBy: CodingKeys.self)
            self = .object(
                code: try object.decodeIfPresent(String.self, forKey: .code),
                message: try object.decodeIfPresent(String.self, forKey: .message)
            )
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    /// 此值可从 App bundle 中提取，仅用于登录的 Turnstile 兼容标记；不是秘密，也不是授权凭据。
    private let appClientKey: String

    private let session: URLSession
    private let keychain: KeychainStore
    private let configuration: AppConfiguration

    /// 401 → refresh 的 single-flight 去重：并发请求共享同一个 in-flight refresh task 的结果，
    /// 避免各自触发 /api/auth/refresh。用锁保护，因为 APIClient 不是 actor，可能被多线程并发调用。
    private let refreshLock = NSLock()
    private var refreshTask: Task<Bool, Never>?

    init(
        session: URLSession? = nil,
        keychain: KeychainStore = .shared,
        configuration: AppConfiguration = AppConfiguration(),
        appClientKey: String = "3da352b803d086be8ba6d1cc7bb400829a3acb322476df5f"
    ) {
        self.session = session ?? Self.makeDefaultSession()
        self.keychain = keychain
        self.configuration = configuration
        self.appClientKey = appClientKey
    }

    static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }

    /// base URL 由 AppConfiguration 统一解析，Debug override 生效时立即使用。
    var baseURL: URL {
        configuration.baseURL
    }

    /// 通用请求：凭据类型必须由调用者显式选择；只有学习凭据会在 401 后 refresh。
    @discardableResult
    func request(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        credential: RequestCredential = .learning
    ) async throws -> Data {
        try await performRequest(
            path: path, method: method, body: body, credential: credential, allowRefresh: true
        )
    }

    func get<T: Decodable>(
        _ path: String, credential: RequestCredential = .learning
    ) async throws -> T {
        let data = try await request(path, method: "GET", credential: credential)
        return try decode(T.self, from: data)
    }

    func post<Body: Encodable, T: Decodable>(
        _ path: String, body: Body, credential: RequestCredential = .learning
    ) async throws -> T {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decoding(error)
        }
        let data = try await request(path, method: "POST", body: encoded, credential: credential)
        return try decode(T.self, from: data)
    }

    // 兼容现有调用点；新增账号生命周期代码只使用 credential 参数。
    @discardableResult
    func request(
        _ path: String, method: String = "GET", body: Data? = nil, authorized: Bool
    ) async throws -> Data {
        try await request(
            path, method: method, body: body, credential: authorized ? .learning : .none
        )
    }

    func get<T: Decodable>(_ path: String, authorized: Bool) async throws -> T {
        try await get(path, credential: authorized ? .learning : .none)
    }

    func post<Body: Encodable, T: Decodable>(
        _ path: String, body: Body, authorized: Bool
    ) async throws -> T {
        try await post(path, body: body, credential: authorized ? .learning : .none)
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }

            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date"
            )
        }
        return decoder
    }

    // MARK: - Private

    private func performRequest(
        path: String,
        method: String,
        body: Data?,
        credential: RequestCredential,
        allowRefresh: Bool
    ) async throws -> Data {
        guard let endpoint = makeEndpoint(for: path) else { throw APIError.invalidURL }

        var urlRequest = URLRequest(url: endpoint.url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if endpoint.normalizedPath == "/api/auth/login" {
            urlRequest.setValue(appClientKey, forHTTPHeaderField: "X-App-Client")
        }
        if let body {
            urlRequest.httpBody = body
        }
        switch credential {
        case .none:
            break
        case .learning:
            if let tokens = keychain.loadTokens() {
                urlRequest.setValue("Bearer \(tokens.access)", forHTTPHeaderField: "Authorization")
            }
        case .management(let token):
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401, case .learning = credential, allowRefresh {
            if await refreshTokens() {
                return try await performRequest(
                    path: path,
                    method: method,
                    body: body,
                    credential: credential,
                    allowRefresh: false
                )
            } else {
                keychain.clear()
                NotificationCenter.default.post(name: .authDidLogout, object: nil)
                throw APIError.unauthorized
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let fallback = "请求失败（\(http.statusCode)）"
            let detail = (try? Self.makeDecoder().decode(ErrorEnvelope.self, from: data))?.detail
            switch detail {
            case .text(let message):
                throw APIError.server(status: http.statusCode, code: nil, message: message)
            case .object(let code, let message):
                let safeMessage = message.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
                throw APIError.server(
                    status: http.statusCode,
                    code: code,
                    message: safeMessage
                )
            case nil:
                throw APIError.server(status: http.statusCode, code: nil, message: fallback)
            }
        }

        return data
    }

    /// 用 Keychain 中的 refresh token 换取新 token 对；成功则写回 Keychain。
    /// single-flight：并发调用共享同一个 in-flight task 的结果，避免各自打 /api/auth/refresh；
    /// task 完成后置 nil，下次 401 会重新发起。
    private func refreshTokens() async -> Bool {
        refreshLock.lock()
        if let existing = refreshTask {
            refreshLock.unlock()
            return await existing.value
        }
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            return await self.performRefresh()
        }
        refreshTask = task
        refreshLock.unlock()

        let result = await task.value

        // 仅创建者（未走上面 existing 分支的那一路）会执行到这里，负责清空，
        // 让下一次 401 能重新发起 refresh。
        refreshLock.lock()
        refreshTask = nil
        refreshLock.unlock()

        return result
    }

    private func performRefresh() async -> Bool {
        guard let tokens = keychain.loadTokens() else { return false }
        do {
            let body = try JSONEncoder().encode(RefreshRequest(refreshToken: tokens.refresh))
            let data = try await performRequest(
                path: "/api/auth/refresh",
                method: "POST",
                body: body,
                credential: .none,
                allowRefresh: false
            )
            let decoded = try Self.makeDecoder().decode(TokenResponse.self, from: data)
            return keychain.saveTokens(access: decoded.accessToken, refresh: decoded.refreshToken)
        } catch {
            return false
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try Self.makeDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func makeEndpoint(for rawPath: String) -> (url: URL, normalizedPath: String)? {
        guard rawPath.hasPrefix("/"), var components = URLComponents(string: rawPath),
              components.scheme == nil, components.host == nil,
              components.user == nil, components.password == nil else {
            return nil
        }

        let rawPercentEncodedPath = components.percentEncodedPath
        guard isAPIPath(rawPercentEncodedPath),
              let normalizedPath = normalizeAPIPath(rawPercentEncodedPath),
              isAPIPath(normalizedPath) else {
            return nil
        }
        components.percentEncodedPath = normalizedPath

        guard let relativeURL = components.url,
              let resolvedURL = URL(string: relativeURL.relativeString, relativeTo: baseURL)?.absoluteURL,
              hasSameOrigin(resolvedURL, as: baseURL) else {
            return nil
        }

        return (resolvedURL, normalizedPath)
    }

    private func isAPIPath(_ path: String) -> Bool {
        path == "/api" || path.hasPrefix("/api/")
    }

    private func normalizeAPIPath(_ percentEncodedPath: String) -> String? {
        var normalizedSegments: [String] = []
        for segment in percentEncodedPath.split(separator: "/", omittingEmptySubsequences: true) {
            let encodedSegment = String(segment)
            let decodedSegment = encodedSegment.removingPercentEncoding ?? encodedSegment
            switch decodedSegment {
            case ".":
                continue
            case "..":
                guard !normalizedSegments.isEmpty else { return nil }
                normalizedSegments.removeLast()
            default:
                guard !decodedSegment.contains("/") && !decodedSegment.contains("\\") else { return nil }
                normalizedSegments.append(encodedSegment)
            }
        }
        return "/" + normalizedSegments.joined(separator: "/")
    }

    private func hasSameOrigin(_ url: URL, as baseURL: URL) -> Bool {
        url.scheme?.lowercased() == baseURL.scheme?.lowercased()
            && url.host?.lowercased() == baseURL.host?.lowercased()
            && url.port == baseURL.port
    }

    private func mapTransportError(_ error: Error) -> APIError {
        let urlError: URLError?
        if let error = error as? URLError {
            urlError = error
        } else {
            let nsError = error as NSError
            urlError = nsError.domain == NSURLErrorDomain
                ? URLError(URLError.Code(rawValue: nsError.code))
                : nil
        }

        switch urlError?.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .networkUnavailable
        case .timedOut:
            return .timeout
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .appTransportSecurityRequiresSecureConnection:
            return .secureConnectionFailed
        default:
            return .transport(error)
        }
    }
}
