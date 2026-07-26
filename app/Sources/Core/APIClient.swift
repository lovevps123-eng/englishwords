// APIClient.swift — 网络层：base URL 解析、JWT 附带、401 自动 refresh 重试一次
import Foundation

extension Notification.Name {
    /// refresh 也失败时广播，AuthStore 监听后登出回登录页
    static let authDidLogout = Notification.Name("APIClient.authDidLogout")
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case server(status: Int, message: String)
    case unauthorized
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址无效"
        case .invalidResponse:
            return "服务器响应异常"
        case .server(_, let message):
            return message
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .decoding:
            return "数据解析失败"
        }
    }
}

/// 后端 FastAPI HTTPException 的标准错误体：{"detail": "..."}
private struct ErrorDetail: Decodable {
    let detail: String?
}

final class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let keychain: KeychainStore

    init(session: URLSession = .shared, keychain: KeychainStore = .shared) {
        self.session = session
        self.keychain = keychain
    }

    /// base URL：从 UserDefaults "serverBaseURL" 读取（设置页 Task 5 才提供写入 UI），
    /// 未设置时回退到生产默认地址。
    var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "serverBaseURL")
        let candidate = (stored?.isEmpty == false) ? stored! : "http://202.182.116.2"
        return URL(string: candidate) ?? URL(string: "http://202.182.116.2")!
    }

    /// 通用请求：自动附 Authorization: Bearer；401 时用 refresh token 重试一次，
    /// 仍失败则清空 Keychain 并广播 authDidLogout。
    @discardableResult
    func request(_ path: String, method: String = "GET", body: Data? = nil, authorized: Bool = true) async throws -> Data {
        try await performRequest(path: path, method: method, body: body, authorized: authorized, allowRefresh: true)
    }

    func get<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
        let data = try await request(path, method: "GET", authorized: authorized)
        return try decode(T.self, from: data)
    }

    func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, authorized: Bool = true) async throws -> T {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decoding(error)
        }
        let data = try await request(path, method: "POST", body: encoded, authorized: authorized)
        return try decode(T.self, from: data)
    }

    // MARK: - Private

    private func performRequest(
        path: String, method: String, body: Data?, authorized: Bool, allowRefresh: Bool
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            urlRequest.httpBody = body
        }
        if authorized, let tokens = keychain.loadTokens() {
            urlRequest.setValue("Bearer \(tokens.access)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw error
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        if http.statusCode == 401, authorized, allowRefresh {
            if await refreshTokens() {
                return try await performRequest(
                    path: path, method: method, body: body, authorized: authorized, allowRefresh: false
                )
            } else {
                keychain.clear()
                NotificationCenter.default.post(name: .authDidLogout, object: nil)
                throw APIError.unauthorized
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorDetail.self, from: data))?.detail
                ?? "请求失败（\(http.statusCode)）"
            throw APIError.server(status: http.statusCode, message: message)
        }

        return data
    }

    /// 用 Keychain 中的 refresh token 换取新 token 对；成功则写回 Keychain。
    private func refreshTokens() async -> Bool {
        guard let tokens = keychain.loadTokens() else { return false }
        do {
            let body = try JSONEncoder().encode(RefreshRequest(refreshToken: tokens.refresh))
            let data = try await performRequest(
                path: "/api/auth/refresh", method: "POST", body: body, authorized: false, allowRefresh: false
            )
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            keychain.saveTokens(access: decoded.accessToken, refresh: decoded.refreshToken)
            return true
        } catch {
            return false
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
