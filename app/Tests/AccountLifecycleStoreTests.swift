import XCTest
@testable import EnglishWords

@MainActor
private final class FakeAccountLifecycleClient: AccountLifecycleClient {
    var regions = [PublicRegion(id: "region-1", name: "北京")]
    var registrationResponse = RegistrationResponse(
        message: "注册申请已提交，请等待管理员审核后登录",
        status: .pendingApproval,
        pendingApproval: true
    )
    var sessionResponse = AccountSessionResponse(
        accountManagementToken: "management-token",
        tokenType: "bearer",
        expiresIn: 600
    )
    var statusResponse = AccountStatusResponse(
        accountStatus: .pendingApproval,
        rejectionReason: nil,
        deletionRequest: nil,
        deletionPolicy: DeletionPolicySummary(enabled: false, policyVersion: nil, slaDays: nil)
    )
    var registrationError: Error?
    var smsError: Error?
    var sessionError: Error?
    var statusError: Error?
    var deletionResponse = DeletionRequestResponse(
        id: "deletion-1",
        status: .requested,
        policyVersion: "2026-09-06",
        requestedAt: Date(timeIntervalSince1970: 1_000),
        dueAt: Date(timeIntervalSince1970: 2_000),
        receiptExpiresAt: nil,
        cancelledAt: nil,
        completedAt: nil,
        receipt: "receipt-1",
        idempotent: false
    )
    var cancellationResponse = CancellationResponse(
        id: "deletion-1",
        status: .cancelled,
        requestedAt: Date(timeIntervalSince1970: 1_000),
        dueAt: Date(timeIntervalSince1970: 2_000),
        receiptExpiresAt: Date(timeIntervalSince1970: 3_000),
        cancelledAt: Date(timeIntervalSince1970: 1_500),
        completedAt: nil,
        idempotent: false
    )
    var receiptStatusResponse = ReceiptStatusResponse(
        status: .requested,
        requestedAt: Date(timeIntervalSince1970: 1_000),
        dueAt: Date(timeIntervalSince1970: 2_000),
        completedAt: nil,
        cancelledAt: nil,
        failureCategory: nil
    )
    var deletionError: Error?
    var cancellationError: Error?
    var receiptStatusError: Error?
    var deletionDelayNanoseconds: UInt64 = 0
    var registrationDelayNanoseconds: UInt64 = 0

    private(set) var registrationRequests: [RegistrationRequest] = []
    private(set) var sessionRequests: [AccountSessionRequest] = []
    private(set) var statusTokens: [String] = []
    private(set) var smsPhones: [String] = []
    private(set) var deletionRequests: [(DeletionRequestCommand, String)] = []
    private(set) var cancellationTokens: [String] = []
    private(set) var queriedReceipts: [String] = []

    func loadRegions() async throws -> [PublicRegion] { regions }

    func sendSMS(to phone: String) async throws {
        smsPhones.append(phone)
        if let smsError { throw smsError }
    }

    func register(_ request: RegistrationRequest) async throws -> RegistrationResponse {
        registrationRequests.append(request)
        if registrationDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: registrationDelayNanoseconds)
        }
        if let registrationError { throw registrationError }
        return registrationResponse
    }

    func createManagementSession(_ request: AccountSessionRequest) async throws -> AccountSessionResponse {
        sessionRequests.append(request)
        if let sessionError { throw sessionError }
        return sessionResponse
    }

    func loadAccountStatus(managementToken: String) async throws -> AccountStatusResponse {
        statusTokens.append(managementToken)
        if let statusError { throw statusError }
        return statusResponse
    }

    func requestDeletion(
        _ command: DeletionRequestCommand, managementToken: String
    ) async throws -> DeletionRequestResponse {
        deletionRequests.append((command, managementToken))
        if deletionDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: deletionDelayNanoseconds)
        }
        if let deletionError { throw deletionError }
        return deletionResponse
    }

    func cancelDeletion(managementToken: String) async throws -> CancellationResponse {
        cancellationTokens.append(managementToken)
        if let cancellationError { throw cancellationError }
        return cancellationResponse
    }

    func loadReceiptStatus(receipt: String) async throws -> ReceiptStatusResponse {
        queriedReceipts.append(receipt)
        if let receiptStatusError { throw receiptStatusError }
        return receiptStatusResponse
    }
}

private final class FakeDeletionReceiptStore: DeletionReceiptStoring {
    var receipt: String?
    var saveSucceeds = true
    private(set) var savedReceipts: [String] = []
    private(set) var clearCount = 0

    func saveDeletionReceipt(_ receipt: String) -> Bool {
        savedReceipts.append(receipt)
        guard saveSucceeds else { return false }
        self.receipt = receipt
        return true
    }

    func loadDeletionReceipt() -> String? { receipt }

    func clearDeletionReceipt() -> Bool {
        clearCount += 1
        receipt = nil
        return true
    }
}

private final class FakeAccountDataCleaner: AccountDataCleaning {
    private(set) var clearCount = 0
    private let receiptStore: DeletionReceiptStoring?

    init(receiptStore: DeletionReceiptStoring? = nil) {
        self.receiptStore = receiptStore
    }

    func clearAfterConfirmedDeletion() {
        clearCount += 1
        receiptStore?.clearDeletionReceipt()
    }
}

@MainActor
final class AccountLifecycleStoreTests: XCTestCase {
    func testLoadingRegionsSelectsFirstValidRegion() async {
        let client = FakeAccountLifecycleClient()
        client.regions = [
            PublicRegion(id: "north", name: "北区"),
            PublicRegion(id: "south", name: "南区"),
        ]
        let store = AccountLifecycleStore(client: client)

        await store.loadRegions()

        XCTAssertEqual(store.regions, client.regions)
        XCTAssertEqual(store.registrationRegionId, "north")
    }

    func testRegistrationRequiresChallengeAndSubmitsPendingRequestWithOptionalSMS() async throws {
        let client = FakeAccountLifecycleClient()
        let store = AccountLifecycleStore(client: client)
        fillValidRegistration(on: store)

        await store.submitRegistration()
        XCTAssertTrue(client.registrationRequests.isEmpty)
        XCTAssertEqual(store.state, .failure("请先完成人机验证"))

        store.registrationPassword = "Password123"
        store.registrationPasswordConfirmation = "Password123"
        store.registrationChallengeToken = "challenge-token"
        store.registrationSMSCode = "   "
        await store.submitRegistration()

        let request = try XCTUnwrap(client.registrationRequests.first)
        XCTAssertEqual(request.phone, "13800000000")
        XCTAssertEqual(request.name, "测试学生")
        XCTAssertEqual(request.grade, "高二")
        XCTAssertEqual(request.school, "测试中学")
        XCTAssertEqual(request.regionId, "region-1")
        XCTAssertNil(request.smsCode)
        XCTAssertEqual(request.turnstileToken, "challenge-token")
        XCTAssertEqual(store.registrationPendingMessage, client.registrationResponse.message)
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertTrue(store.registrationPassword.isEmpty)
        XCTAssertTrue(store.registrationPasswordConfirmation.isEmpty)
        XCTAssertTrue(store.registrationChallengeToken.isEmpty)
    }

    func testRegistrationSuppressesDuplicateTapWhileRequestIsInFlight() async {
        let client = FakeAccountLifecycleClient()
        client.registrationDelayNanoseconds = 50_000_000
        let store = AccountLifecycleStore(client: client)
        fillValidRegistration(on: store)
        store.registrationChallengeToken = "challenge-token"

        let first = Task { await store.submitRegistration() }
        await Task.yield()
        await store.submitRegistration()
        await first.value

        XCTAssertEqual(client.registrationRequests.count, 1)
    }

    func testRegistrationNetworkFailurePreservesNonSecretsAndClearsSecrets() async {
        let client = FakeAccountLifecycleClient()
        client.registrationError = APIError.networkUnavailable
        let store = AccountLifecycleStore(client: client)
        fillValidRegistration(on: store)
        store.registrationChallengeToken = "challenge-token"

        await store.submitRegistration()

        XCTAssertEqual(store.registrationPhone, "13800000000")
        XCTAssertEqual(store.registrationName, "测试学生")
        XCTAssertEqual(store.registrationRegionId, "region-1")
        XCTAssertTrue(store.registrationPassword.isEmpty)
        XCTAssertTrue(store.registrationPasswordConfirmation.isEmpty)
        XCTAssertTrue(store.registrationChallengeToken.isEmpty)
        XCTAssertEqual(store.state, .failure("网络不可用，请检查网络后重试"))
    }

    func testSMSFailurePreservesRegistrationFieldsAndClearsSecrets() async {
        let client = FakeAccountLifecycleClient()
        client.smsError = APIError.networkUnavailable
        let store = AccountLifecycleStore(client: client)
        fillValidRegistration(on: store)
        store.registrationChallengeToken = "challenge-token"

        await store.sendRegistrationSMS()

        XCTAssertEqual(store.registrationPhone, "13800000000")
        XCTAssertEqual(store.registrationName, "测试学生")
        XCTAssertEqual(store.registrationRegionId, "region-1")
        XCTAssertTrue(store.registrationPassword.isEmpty)
        XCTAssertTrue(store.registrationPasswordConfirmation.isEmpty)
        XCTAssertTrue(store.registrationChallengeToken.isEmpty)
        XCTAssertEqual(store.state, .failure("网络不可用，请检查网络后重试"))
    }

    func testChallengeFailurePreservesNonSecretsAndClearsBothFlowSecrets() {
        let store = AccountLifecycleStore(client: FakeAccountLifecycleClient())
        fillValidRegistration(on: store)
        store.registrationChallengeToken = "registration-challenge"
        store.managementPhone = "13900000000"
        store.managementPassword = "Management123"
        store.managementChallengeToken = "management-challenge"

        store.challengeFailed("人机验证失败，请重试")

        XCTAssertEqual(store.registrationPhone, "13800000000")
        XCTAssertEqual(store.registrationName, "测试学生")
        XCTAssertEqual(store.managementPhone, "13900000000")
        XCTAssertTrue(store.registrationPassword.isEmpty)
        XCTAssertTrue(store.registrationPasswordConfirmation.isEmpty)
        XCTAssertTrue(store.registrationChallengeToken.isEmpty)
        XCTAssertTrue(store.managementPassword.isEmpty)
        XCTAssertTrue(store.managementChallengeToken.isEmpty)
        XCTAssertEqual(store.state, .failure("人机验证失败，请重试"))
    }

    func testUnknownAndWrongPasswordUseSameManagementFailure() async {
        let errors = [
            APIError.server(status: 401, code: "ACCOUNT_CREDENTIALS_INVALID", message: "请求失败（401）"),
            APIError.server(status: 401, code: "ACCOUNT_CREDENTIALS_INVALID", message: "手机号不存在"),
        ]

        for error in errors {
            let client = FakeAccountLifecycleClient()
            client.sessionError = error
            let store = AccountLifecycleStore(client: client)
            store.managementPhone = "13800000000"
            store.managementPassword = "WrongPassword1"
            store.managementChallengeToken = "challenge-token"

            await store.authenticateAndLoadStatus()

            XCTAssertEqual(store.state, .failure("手机号或密码错误"))
            XCTAssertEqual(store.managementPhone, "13800000000")
            XCTAssertTrue(store.managementPassword.isEmpty)
            XCTAssertTrue(store.managementChallengeToken.isEmpty)
        }
    }

    func testManagementSessionPresentsEveryRestrictedAccountStatus() async {
        for status in [
            AccountStatus.pendingApproval, .rejected, .disabled, .deleting,
        ] {
            let client = FakeAccountLifecycleClient()
            client.statusResponse = AccountStatusResponse(
                accountStatus: status,
                rejectionReason: status == .rejected ? "资料不完整" : nil,
                deletionRequest: nil,
                deletionPolicy: DeletionPolicySummary(enabled: false, policyVersion: nil, slaDays: nil)
            )
            let store = AccountLifecycleStore(client: client)
            store.managementPhone = "13800000000"
            store.managementPassword = "Password123"
            store.managementChallengeToken = "challenge-token"

            await store.authenticateAndLoadStatus()

            XCTAssertEqual(store.state, .status(client.statusResponse))
            XCTAssertEqual(client.statusTokens, ["management-token"])
        }
    }

    func testExpiredOrDismissedManagementSessionCannotRefreshStatus() async {
        let client = FakeAccountLifecycleClient()
        var now = Date(timeIntervalSince1970: 1_000)
        let store = AccountLifecycleStore(client: client, now: { now })
        store.managementPhone = "13800000000"
        store.managementPassword = "Password123"
        store.managementChallengeToken = "challenge-token"
        await store.authenticateAndLoadStatus()
        XCTAssertEqual(client.statusTokens.count, 1)

        now = Date(timeIntervalSince1970: 1_601)
        await store.refreshStatus()
        XCTAssertEqual(store.state, .failure("账号管理会话已过期，请重新验证"))
        XCTAssertEqual(client.statusTokens.count, 1)

        store.dismissManagement()
        await store.refreshStatus()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(client.statusTokens.count, 1)
    }

    func testAuthStoreRecognizesRestrictedLoginStatusCodes() {
        XCTAssertEqual(AuthStore.restrictedStatus(forServerCode: "ACCOUNT_PENDING_APPROVAL"), .pendingApproval)
        XCTAssertEqual(AuthStore.restrictedStatus(forServerCode: "ACCOUNT_REJECTED"), .rejected)
        XCTAssertEqual(AuthStore.restrictedStatus(forServerCode: "ACCOUNT_DISABLED"), .disabled)
        XCTAssertEqual(AuthStore.restrictedStatus(forServerCode: "ACCOUNT_DELETING"), .deleting)
        XCTAssertNil(AuthStore.restrictedStatus(forServerCode: "ACCOUNT_CREDENTIALS_INVALID"))
    }

    func testDeletionRequestRequiresExactConfirmationAndUsesCurrentPolicyWithOptionalReason() async throws {
        let client = FakeAccountLifecycleClient()
        let receipts = FakeDeletionReceiptStore()
        let store = AccountLifecycleStore(client: client, receiptStore: receipts)
        await authenticateActiveAccount(store, client: client)

        store.deletionConfirmation = "delete_account"
        store.deletionReason = "  不再使用  "
        await store.requestDeletion()
        XCTAssertTrue(client.deletionRequests.isEmpty)
        XCTAssertEqual(store.state, .failure("请输入 DELETE_ACCOUNT 确认注销"))

        await authenticateActiveAccount(store, client: client)
        store.deletionConfirmation = "DELETE_ACCOUNT"
        store.deletionReason = "  不再使用  "
        await store.requestDeletion()

        let (command, token) = try XCTUnwrap(client.deletionRequests.first)
        XCTAssertEqual(command.confirmation, "DELETE_ACCOUNT")
        XCTAssertEqual(command.policyVersion, "2026-09-06")
        XCTAssertEqual(command.reason, "不再使用")
        XCTAssertEqual(token, "management-token")
        XCTAssertEqual(receipts.receipt, "receipt-1")
        XCTAssertEqual(store.currentDeletionStatus, .requested)
    }

    func testDeletionRequestDoesNotShowSuccessWhenReceiptCannotBePersisted() async {
        let client = FakeAccountLifecycleClient()
        let receipts = FakeDeletionReceiptStore()
        receipts.saveSucceeds = false
        let store = AccountLifecycleStore(client: client, receiptStore: receipts)
        await authenticateActiveAccount(store, client: client)
        store.deletionConfirmation = "DELETE_ACCOUNT"

        await store.requestDeletion()

        XCTAssertEqual(receipts.savedReceipts, ["receipt-1"])
        XCTAssertEqual(store.state, .failure("无法安全保存注销回执，请重试"))
        XCTAssertNil(store.currentDeletionStatus)
    }

    func testIdempotentDeletionResponseUsesAlreadyPersistedReceipt() async {
        let client = FakeAccountLifecycleClient()
        client.deletionResponse = DeletionRequestResponse(
            id: "deletion-1", status: .requested, policyVersion: "2026-09-06",
            requestedAt: Date(timeIntervalSince1970: 1_000),
            dueAt: Date(timeIntervalSince1970: 2_000), receiptExpiresAt: nil,
            cancelledAt: nil, completedAt: nil, receipt: nil, idempotent: true
        )
        let receipts = FakeDeletionReceiptStore()
        receipts.receipt = "existing-receipt"
        let store = AccountLifecycleStore(client: client, receiptStore: receipts)
        await authenticateActiveAccount(store, client: client)
        store.deletionConfirmation = "DELETE_ACCOUNT"

        await store.requestDeletion()

        XCTAssertTrue(receipts.savedReceipts.isEmpty)
        XCTAssertEqual(receipts.receipt, "existing-receipt")
        XCTAssertEqual(store.currentDeletionStatus, .requested)
    }

    func testCancellationIsAllowedOnlyWhileRequested() async {
        let client = FakeAccountLifecycleClient()
        let receipts = FakeDeletionReceiptStore()
        receipts.receipt = "receipt-1"
        let store = AccountLifecycleStore(client: client, receiptStore: receipts)
        await authenticateActiveAccount(store, client: client)
        store.deletionConfirmation = "DELETE_ACCOUNT"
        await store.requestDeletion()
        client.statusResponse = Self.activeStatus(deletionStatus: .cancelled)

        await store.cancelDeletion()

        XCTAssertEqual(client.cancellationTokens, ["management-token"])
        XCTAssertEqual(client.statusTokens.count, 2, "撤回后应从服务器读取恢复后的账号状态")
        XCTAssertEqual(store.currentDeletionStatus, .cancelled)

        client.statusResponse = Self.activeStatus(deletionStatus: .processing)
        await authenticateActiveAccount(store, client: client)
        await store.cancelDeletion()
        XCTAssertEqual(client.cancellationTokens, ["management-token"])
        XCTAssertEqual(store.state, .failure("仅已收到、尚未处理的申请可以撤回"))
    }

    func testReceiptStatusCanBeQueriedWithoutManagementOrLearningSession() async {
        let client = FakeAccountLifecycleClient()
        let receipts = FakeDeletionReceiptStore()
        receipts.receipt = "persisted-receipt"
        let store = AccountLifecycleStore(client: client, receiptStore: receipts)

        await store.refreshReceiptStatus()

        XCTAssertEqual(client.queriedReceipts, ["persisted-receipt"])
        XCTAssertEqual(store.state, .receiptStatus(client.receiptStatusResponse))
    }

    func testOnlyExplicitCompletedReceiptStatusTriggersCleanupAndRetainsVisibleConfirmation() async {
        let client = FakeAccountLifecycleClient()
        client.receiptStatusResponse = ReceiptStatusResponse(
            status: .completed,
            requestedAt: Date(timeIntervalSince1970: 1_000),
            dueAt: Date(timeIntervalSince1970: 2_000),
            completedAt: Date(timeIntervalSince1970: 1_800),
            cancelledAt: nil,
            failureCategory: nil
        )
        let receipts = FakeDeletionReceiptStore()
        receipts.receipt = "persisted-receipt"
        let cleaner = FakeAccountDataCleaner(receiptStore: receipts)
        let store = AccountLifecycleStore(
            client: client, receiptStore: receipts, dataCleaner: cleaner
        )

        await store.refreshReceiptStatus()

        XCTAssertEqual(cleaner.clearCount, 1)
        XCTAssertNil(receipts.receipt)
        XCTAssertEqual(receipts.clearCount, 1)
        XCTAssertFalse(store.hasDeletionReceipt)
        XCTAssertEqual(store.state, .deletionCompleted(client.receiptStatusResponse))
    }

    func testNonCompletedStatusesAndReceiptFailuresNeverClearLocalData() async {
        let nonCompleted: [DeletionRequestStatus] = [
            .requested, .processing, .failed, .cancelled,
        ]
        for status in nonCompleted {
            let client = FakeAccountLifecycleClient()
            client.receiptStatusResponse = ReceiptStatusResponse(
                status: status,
                requestedAt: Date(timeIntervalSince1970: 1_000),
                dueAt: Date(timeIntervalSince1970: 2_000),
                completedAt: nil,
                cancelledAt: status == .cancelled ? Date(timeIntervalSince1970: 1_500) : nil,
                failureCategory: status == .failed ? "external_file_failure" : nil
            )
            let receipts = FakeDeletionReceiptStore()
            receipts.receipt = "persisted-receipt"
            let cleaner = FakeAccountDataCleaner()
            let store = AccountLifecycleStore(
                client: client, receiptStore: receipts, dataCleaner: cleaner
            )

            await store.refreshReceiptStatus()

            XCTAssertEqual(cleaner.clearCount, 0, "\(status) 不得触发清理")
            XCTAssertEqual(receipts.receipt, "persisted-receipt")
            XCTAssertEqual(store.state, .receiptStatus(client.receiptStatusResponse))
        }

        let errors: [APIError] = [
            .server(status: 401, code: nil, message: "请求失败（401）"),
            .timeout,
            .networkUnavailable,
            .server(status: 404, code: "ACCOUNT_DELETION_RECEIPT_NOT_FOUND", message: "未找到"),
        ]
        for error in errors {
            let client = FakeAccountLifecycleClient()
            client.receiptStatusError = error
            let receipts = FakeDeletionReceiptStore()
            receipts.receipt = "persisted-receipt"
            let cleaner = FakeAccountDataCleaner()
            let store = AccountLifecycleStore(
                client: client, receiptStore: receipts, dataCleaner: cleaner
            )

            await store.refreshReceiptStatus()

            XCTAssertEqual(cleaner.clearCount, 0)
            XCTAssertEqual(receipts.receipt, "persisted-receipt")
            XCTAssertEqual(receipts.clearCount, 0)
        }
    }

    func testDeletionSubmissionSuppressesDuplicateTapWhileInFlight() async {
        let client = FakeAccountLifecycleClient()
        client.deletionDelayNanoseconds = 50_000_000
        let receipts = FakeDeletionReceiptStore()
        let store = AccountLifecycleStore(client: client, receiptStore: receipts)
        await authenticateActiveAccount(store, client: client)
        store.deletionConfirmation = "DELETE_ACCOUNT"

        let first = Task { await store.requestDeletion() }
        await Task.yield()
        XCTAssertTrue(store.isDeletionInFlight)
        await store.requestDeletion()
        await first.value

        XCTAssertEqual(client.deletionRequests.count, 1)
        XCTAssertFalse(store.isDeletionInFlight)
    }

    private func fillValidRegistration(on store: AccountLifecycleStore) {
        store.registrationPhone = "13800000000"
        store.registrationPassword = "Password123"
        store.registrationPasswordConfirmation = "Password123"
        store.registrationName = "测试学生"
        store.registrationGrade = "高二"
        store.registrationSchool = "测试中学"
        store.registrationRegionId = "region-1"
    }

    private func authenticateActiveAccount(
        _ store: AccountLifecycleStore, client: FakeAccountLifecycleClient
    ) async {
        client.statusResponse = Self.activeStatus()
        store.managementPhone = "13800000000"
        store.managementPassword = "Password123"
        store.managementChallengeToken = "challenge-token"
        await store.authenticateAndLoadStatus()
    }

    private static func activeStatus(
        deletionStatus: DeletionRequestStatus? = nil
    ) -> AccountStatusResponse {
        AccountStatusResponse(
            accountStatus: deletionStatus == nil || deletionStatus == .cancelled ? .active : .deleting,
            rejectionReason: nil,
            deletionRequest: deletionStatus.map {
                DeletionStatusSummary(
                    status: $0,
                    requestedAt: Date(timeIntervalSince1970: 1_000),
                    dueAt: Date(timeIntervalSince1970: 2_000),
                    completedAt: nil,
                    cancelledAt: nil,
                    failureCategory: nil
                )
            },
            deletionPolicy: DeletionPolicySummary(
                enabled: true, policyVersion: "2026-09-06", slaDays: 7
            )
        )
    }
}
