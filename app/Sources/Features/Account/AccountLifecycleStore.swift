import Foundation
import Observation

enum AccountLifecycleScreenState: Equatable {
    case signedOut
    case authenticating
    case status(AccountStatusResponse)
    case receiptStatus(ReceiptStatusResponse)
    case deletionCompleted(ReceiptStatusResponse)
    case submitting
    case failure(String)
}

protocol DeletionReceiptStoring: AnyObject {
    @discardableResult func saveDeletionReceipt(_ receipt: String) -> Bool
    func loadDeletionReceipt() -> String?
    @discardableResult func clearDeletionReceipt() -> Bool
}

extension KeychainStore: DeletionReceiptStoring {}

protocol AccountDataCleaning: AnyObject {
    func clearAfterConfirmedDeletion()
}

protocol AccountLifecycleClient {
    func loadRegions() async throws -> [PublicRegion]
    func sendSMS(to phone: String) async throws
    func register(_ request: RegistrationRequest) async throws -> RegistrationResponse
    func createManagementSession(_ request: AccountSessionRequest) async throws -> AccountSessionResponse
    func loadAccountStatus(managementToken: String) async throws -> AccountStatusResponse
    func requestDeletion(
        _ command: DeletionRequestCommand, managementToken: String
    ) async throws -> DeletionRequestResponse
    func cancelDeletion(managementToken: String) async throws -> CancellationResponse
    func loadReceiptStatus(receipt: String) async throws -> ReceiptStatusResponse
}

extension APIClient: AccountLifecycleClient {
    func loadRegions() async throws -> [PublicRegion] {
        try await get("/api/auth/regions", credential: .none)
    }

    func sendSMS(to phone: String) async throws {
        struct SMSRequest: Encodable { let phone: String }
        struct SMSResponse: Decodable { let message: String }
        let _: SMSResponse = try await post(
            "/api/auth/send-sms", body: SMSRequest(phone: phone), credential: .none
        )
    }

    func register(_ request: RegistrationRequest) async throws -> RegistrationResponse {
        try await post("/api/auth/register", body: request, credential: .none)
    }

    func createManagementSession(_ request: AccountSessionRequest) async throws -> AccountSessionResponse {
        try await post("/api/account/session", body: request, credential: .none)
    }

    func loadAccountStatus(managementToken: String) async throws -> AccountStatusResponse {
        try await get("/api/account/status", credential: .management(managementToken))
    }

    func requestDeletion(
        _ command: DeletionRequestCommand, managementToken: String
    ) async throws -> DeletionRequestResponse {
        try await post(
            "/api/account/deletion-requests",
            body: command,
            credential: .management(managementToken)
        )
    }

    func cancelDeletion(managementToken: String) async throws -> CancellationResponse {
        struct EmptyBody: Encodable {}
        return try await post(
            "/api/account/deletion-requests/cancel",
            body: EmptyBody(),
            credential: .management(managementToken)
        )
    }

    func loadReceiptStatus(receipt: String) async throws -> ReceiptStatusResponse {
        try await post(
            "/api/account/deletion-receipt/status",
            body: DeletionReceiptStatusRequest(receipt: receipt),
            credential: .none
        )
    }
}

@MainActor
@Observable
final class AccountLifecycleStore {
    private(set) var state: AccountLifecycleScreenState = .signedOut
    private(set) var regions: [PublicRegion] = []
    private(set) var registrationPendingMessage: String?
    private(set) var smsMessage: String?
    private(set) var isLoadingRegions = false
    private(set) var isSendingSMS = false
    private(set) var isDeletionInFlight = false
    private(set) var hasDeletionReceipt: Bool
    private(set) var deletionMessage: String?

    var registrationPhone = ""
    var registrationPassword = ""
    var registrationPasswordConfirmation = ""
    var registrationName = ""
    var registrationGrade = ""
    var registrationSchool = ""
    var registrationRegionId = ""
    var registrationSMSCode = ""
    var registrationChallengeToken = ""

    var managementPhone = ""
    var managementPassword = ""
    var managementChallengeToken = ""
    var deletionConfirmation = ""
    var deletionReason = ""

    private let client: AccountLifecycleClient
    private let receiptStore: DeletionReceiptStoring
    private let dataCleaner: AccountDataCleaning?
    private let now: () -> Date
    private var managementToken: String?
    private var managementExpiresAt: Date?
    private var registrationInFlight = false
    private var managementInFlight = false

    init(
        client: AccountLifecycleClient = APIClient.shared,
        receiptStore: DeletionReceiptStoring = KeychainStore.shared,
        dataCleaner: AccountDataCleaning? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.receiptStore = receiptStore
        self.dataCleaner = dataCleaner
        self.now = now
        self.hasDeletionReceipt = receiptStore.loadDeletionReceipt() != nil
    }

    var isRegistering: Bool { registrationInFlight }
    var isManaging: Bool { managementInFlight }

    var currentDeletionStatus: DeletionRequestStatus? {
        switch state {
        case .status(let response): response.deletionRequest?.status
        case .receiptStatus(let response), .deletionCompleted(let response): response.status
        default: nil
        }
    }

    func loadRegions() async {
        guard regions.isEmpty, !isLoadingRegions else { return }
        isLoadingRegions = true
        defer { isLoadingRegions = false }
        do {
            regions = try await client.loadRegions()
            if !regions.contains(where: { $0.id == registrationRegionId }) {
                registrationRegionId = regions.first?.id ?? ""
            }
        } catch {
            state = .failure(message(for: error))
        }
    }

    func sendRegistrationSMS() async {
        guard !isSendingSMS else { return }
        let phone = registrationPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidPhone(phone) else {
            state = .failure("请输入正确的手机号")
            return
        }
        isSendingSMS = true
        smsMessage = nil
        defer { isSendingSMS = false }
        do {
            try await client.sendSMS(to: phone)
            smsMessage = "验证码已发送；如当前环境未启用短信，可留空继续申请"
        } catch {
            clearRegistrationSecrets()
            state = .failure(message(for: error))
        }
    }

    @discardableResult
    func validateRegistrationForChallenge() -> Bool {
        if let validationMessage = registrationValidationMessage() {
            state = .failure(validationMessage)
            return false
        }
        return true
    }

    func submitRegistration() async {
        guard !registrationInFlight else { return }
        guard let request = registrationRequest() else { return }

        registrationInFlight = true
        registrationPendingMessage = nil
        state = .submitting
        defer {
            registrationInFlight = false
            clearRegistrationSecrets()
        }

        do {
            let response = try await client.register(request)
            guard response.status == .pendingApproval, response.pendingApproval else {
                state = .failure("服务器未返回待审核状态，请稍后重试")
                return
            }
            registrationPendingMessage = response.message
            state = .signedOut
        } catch {
            state = .failure(message(for: error))
        }
    }

    @discardableResult
    func validateManagementForChallenge() -> Bool {
        let phone = managementPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidPhone(phone) else {
            state = .failure("请输入正确的手机号")
            return false
        }
        guard !managementPassword.isEmpty else {
            state = .failure("请输入密码")
            return false
        }
        return true
    }

    func authenticateAndLoadStatus() async {
        guard !managementInFlight else { return }
        let phone = managementPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidPhone(phone) else {
            state = .failure("请输入正确的手机号")
            return
        }
        guard !managementPassword.isEmpty else {
            state = .failure("请输入密码")
            return
        }
        let challenge = managementChallengeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !challenge.isEmpty else {
            state = .failure("请先完成人机验证")
            return
        }

        managementInFlight = true
        state = .authenticating
        let password = managementPassword
        defer {
            managementInFlight = false
            clearManagementSecrets()
        }

        do {
            let session = try await client.createManagementSession(AccountSessionRequest(
                phone: phone,
                password: password,
                turnstileToken: challenge
            ))
            managementToken = session.accountManagementToken
            managementExpiresAt = now().addingTimeInterval(TimeInterval(session.expiresIn))
            try await loadStatus(using: session.accountManagementToken)
        } catch {
            clearManagementSession()
            state = .failure(message(for: error))
        }
    }

    func refreshStatus() async {
        guard let managementToken else {
            state = .signedOut
            return
        }
        guard let managementExpiresAt, now() < managementExpiresAt else {
            clearManagementSession()
            state = .failure("账号管理会话已过期，请重新验证")
            return
        }
        do {
            try await loadStatus(using: managementToken)
        } catch {
            if (error as? APIError)?.code == "ACCOUNT_MANAGEMENT_SESSION_INVALID" {
                clearManagementSession()
            }
            state = .failure(message(for: error))
        }
    }

    func requestDeletion() async {
        guard !isDeletionInFlight else { return }
        guard case .status(let accountResponse) = state else {
            state = .failure("请先重新验证账号")
            return
        }
        guard accountResponse.deletionPolicy.enabled,
              let policyVersion = accountResponse.deletionPolicy.policyVersion else {
            state = .failure("账号注销功能尚未启用")
            return
        }
        guard deletionConfirmation == "DELETE_ACCOUNT" else {
            state = .failure("请输入 DELETE_ACCOUNT 确认注销")
            return
        }
        guard let token = validManagementToken() else { return }

        isDeletionInFlight = true
        deletionMessage = nil
        defer { isDeletionInFlight = false }

        do {
            let response = try await client.requestDeletion(
                DeletionRequestCommand(
                    confirmation: "DELETE_ACCOUNT",
                    policyVersion: policyVersion,
                    reason: nilIfBlank(deletionReason)
                ),
                managementToken: token
            )
            if let receipt = response.receipt {
                guard receiptStore.saveDeletionReceipt(receipt) else {
                    state = .failure("无法安全保存注销回执，请重试")
                    return
                }
                hasDeletionReceipt = true
            } else if receiptStore.loadDeletionReceipt() == nil {
                state = .failure("未找到注销回执，请联系管理员")
                return
            }
            hasDeletionReceipt = true
            deletionConfirmation = ""
            deletionReason = ""
            deletionMessage = response.idempotent ? "注销申请已存在" : "注销申请已提交"
            updateDeletionStatus(summary(from: response), in: accountResponse)
        } catch {
            state = .failure(message(for: error))
        }
    }

    func cancelDeletion() async {
        guard !isDeletionInFlight else { return }
        guard case .status(let accountResponse) = state,
              accountResponse.deletionRequest?.status == .requested else {
            state = .failure("仅已收到、尚未处理的申请可以撤回")
            return
        }
        guard let token = validManagementToken() else { return }

        isDeletionInFlight = true
        deletionMessage = nil
        defer { isDeletionInFlight = false }
        do {
            _ = try await client.cancelDeletion(managementToken: token)
            deletionMessage = "注销申请已撤回"
            try await loadStatus(using: token)
        } catch {
            state = .failure(message(for: error))
        }
    }

    func refreshReceiptStatus() async {
        guard !isDeletionInFlight else { return }
        guard let receipt = receiptStore.loadDeletionReceipt(), !receipt.isEmpty else {
            hasDeletionReceipt = false
            state = .failure("本机没有可查询的注销回执")
            return
        }

        isDeletionInFlight = true
        deletionMessage = nil
        defer { isDeletionInFlight = false }
        do {
            let response = try await client.loadReceiptStatus(receipt: receipt)
            guard response.status == .completed else {
                state = .receiptStatus(response)
                return
            }
            guard let dataCleaner else {
                state = .failure("本地账号数据清理尚未就绪，请稍后重试")
                return
            }
            dataCleaner.clearAfterConfirmedDeletion()
            clearManagementSession()
            clearManagementSecrets()
            hasDeletionReceipt = false
            state = .deletionCompleted(response)
        } catch {
            state = .failure(message(for: error))
        }
    }

    func dismissManagement() {
        clearManagementSession()
        clearManagementSecrets()
        state = .signedOut
    }

    func setRegistrationChallengeToken(_ token: String) {
        registrationChallengeToken = token
    }

    func setManagementChallengeToken(_ token: String) {
        managementChallengeToken = token
    }

    func challengeFailed(_ message: String) {
        clearRegistrationSecrets()
        clearManagementSecrets()
        state = .failure(message)
    }

    private func loadStatus(using token: String) async throws {
        state = .status(try await client.loadAccountStatus(managementToken: token))
    }

    private func validManagementToken() -> String? {
        guard let managementToken,
              let managementExpiresAt,
              now() < managementExpiresAt else {
            clearManagementSession()
            state = .failure("账号管理会话已过期，请重新验证")
            return nil
        }
        return managementToken
    }

    private func summary(from response: DeletionRequestResponse) -> DeletionStatusSummary {
        DeletionStatusSummary(
            status: response.status,
            requestedAt: response.requestedAt,
            dueAt: response.dueAt,
            completedAt: response.completedAt,
            cancelledAt: response.cancelledAt,
            failureCategory: nil
        )
    }

    private func updateDeletionStatus(
        _ deletion: DeletionStatusSummary, in accountResponse: AccountStatusResponse
    ) {
        state = .status(AccountStatusResponse(
            accountStatus: deletion.status == .cancelled ? .active : .deleting,
            rejectionReason: accountResponse.rejectionReason,
            deletionRequest: deletion,
            deletionPolicy: accountResponse.deletionPolicy
        ))
    }

    private func registrationRequest() -> RegistrationRequest? {
        if let validationMessage = registrationValidationMessage() {
            state = .failure(validationMessage)
            return nil
        }
        let challenge = registrationChallengeToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !challenge.isEmpty else {
            state = .failure("请先完成人机验证")
            return nil
        }
        return RegistrationRequest(
            phone: registrationPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            password: registrationPassword,
            name: registrationName.trimmingCharacters(in: .whitespacesAndNewlines),
            grade: nilIfBlank(registrationGrade),
            school: nilIfBlank(registrationSchool),
            regionId: registrationRegionId,
            turnstileToken: challenge,
            smsCode: nilIfBlank(registrationSMSCode)
        )
    }

    private func registrationValidationMessage() -> String? {
        guard Self.isValidPhone(registrationPhone.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "请输入正确的手机号"
        }
        guard !registrationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "请输入姓名"
        }
        guard !registrationRegionId.isEmpty else { return "请选择地区" }
        guard registrationPassword.count >= 8,
              registrationPassword.rangeOfCharacter(from: .letters) != nil,
              registrationPassword.rangeOfCharacter(from: .decimalDigits) != nil else {
            return "密码至少 8 位，并包含字母和数字"
        }
        guard registrationPassword == registrationPasswordConfirmation else {
            return "两次输入的密码不一致"
        }
        return nil
    }

    private static func isValidPhone(_ phone: String) -> Bool {
        phone.range(of: #"^1[3-9]\d{9}$"#, options: .regularExpression) != nil
    }

    private func nilIfBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clearRegistrationSecrets() {
        registrationPassword = ""
        registrationPasswordConfirmation = ""
        registrationChallengeToken = ""
    }

    private func clearManagementSecrets() {
        managementPassword = ""
        managementChallengeToken = ""
    }

    private func clearManagementSession() {
        managementToken = nil
        managementExpiresAt = nil
    }

    private func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError.code {
            case "ACCOUNT_CREDENTIALS_INVALID":
                return "手机号或密码错误"
            case "ACCOUNT_SESSION_TURNSTILE_FAILED":
                return "人机验证失败，请重试"
            case "ACCOUNT_SESSION_RATE_LIMITED":
                return "请求过于频繁，请稍后再试"
            case "ACCOUNT_SELF_SERVICE_UNAVAILABLE":
                return "此账号不能使用自助账号管理"
            case "ACCOUNT_DELETION_NOT_ENABLED":
                return "账号注销功能尚未启用"
            case "DELETION_RECEIPT_NOT_FOUND":
                return "注销回执无效或已过期"
            case "ACCOUNT_DELETION_REQUEST_NOT_CANCELLABLE":
                return "申请已开始处理，不能撤回"
            default:
                return apiError.errorDescription ?? "请求失败，请稍后重试"
            }
        }
        return error.localizedDescription
    }
}
