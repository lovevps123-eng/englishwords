// AuthStore.swift — 登录态：持有 isAuthenticated，驱动 App 根视图路由（登录页 ↔ 主 Tab）
import Foundation

@Observable
final class AuthStore {
    private(set) var isAuthenticated: Bool
    var errorMessage: String?
    private(set) var isLoading = false

    private let keychain: KeychainStore
    private let apiClient: APIClient
    private var logoutObserver: NSObjectProtocol?

    init(keychain: KeychainStore = .shared, apiClient: APIClient = .shared) {
        self.keychain = keychain
        self.apiClient = apiClient
        self.isAuthenticated = keychain.loadTokens() != nil

        logoutObserver = NotificationCenter.default.addObserver(
            forName: .authDidLogout, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isAuthenticated = false
        }
    }

    deinit {
        if let logoutObserver {
            NotificationCenter.default.removeObserver(logoutObserver)
        }
    }

    /// 手机号+密码登录。登录逻辑与网页版共用后端 /api/auth/login；
    /// v1 不做注册流程，注册需引导用户去网页版。
    @MainActor
    func login(phone: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let request = LoginRequest(phone: phone, password: password)
            let token: TokenResponse = try await apiClient.post(
                "/api/auth/login", body: request, authorized: false
            )
            let saved = keychain.saveTokens(access: token.accessToken, refresh: token.refreshToken)
            guard saved else {
                errorMessage = "本机安全存储失败，请重试"
                isAuthenticated = false
                return
            }
            isAuthenticated = true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        keychain.clear()
        isAuthenticated = false
    }
}
