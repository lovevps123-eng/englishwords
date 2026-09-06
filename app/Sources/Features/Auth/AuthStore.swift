// AuthStore.swift — 登录态：持有 isAuthenticated，驱动 App 根视图路由（登录页 ↔ 主 Tab）
import Foundation

@Observable
final class AuthStore {
    private(set) var isAuthenticated: Bool
    var errorMessage: String?
    private(set) var isLoading = false
    private(set) var restrictedAccountStatus: AccountStatus?

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
        restrictedAccountStatus = nil
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
            if let apiError = error as? APIError,
               let status = Self.restrictedStatus(forServerCode: apiError.code) {
                restrictedAccountStatus = status
                errorMessage = Self.loginMessage(for: status)
            } else {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func logout() {
        keychain.clear()
        isAuthenticated = false
        restrictedAccountStatus = nil
    }

    static func restrictedStatus(forServerCode code: String?) -> AccountStatus? {
        switch code {
        case "ACCOUNT_PENDING_APPROVAL": .pendingApproval
        case "ACCOUNT_REJECTED": .rejected
        case "ACCOUNT_DISABLED": .disabled
        case "ACCOUNT_DELETING": .deleting
        default: nil
        }
    }

    private static func loginMessage(for status: AccountStatus) -> String {
        switch status {
        case .pendingApproval: "账号正在等待管理员审核"
        case .rejected: "账号申请未通过，请查看申请状态"
        case .disabled: "账号当前已停用，请查看账号状态"
        case .deleting: "账号正在注销处理中"
        case .active: "账号状态异常，请稍后重试"
        }
    }
}
