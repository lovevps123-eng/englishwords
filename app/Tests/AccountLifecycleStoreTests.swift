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
    var sessionError: Error?
    var statusError: Error?
    var registrationDelayNanoseconds: UInt64 = 0

    private(set) var registrationRequests: [RegistrationRequest] = []
    private(set) var sessionRequests: [AccountSessionRequest] = []
    private(set) var statusTokens: [String] = []
    private(set) var smsPhones: [String] = []

    func loadRegions() async throws -> [PublicRegion] { regions }

    func sendSMS(to phone: String) async throws {
        smsPhones.append(phone)
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

    private func fillValidRegistration(on store: AccountLifecycleStore) {
        store.registrationPhone = "13800000000"
        store.registrationPassword = "Password123"
        store.registrationPasswordConfirmation = "Password123"
        store.registrationName = "测试学生"
        store.registrationGrade = "高二"
        store.registrationSchool = "测试中学"
        store.registrationRegionId = "region-1"
    }
}
