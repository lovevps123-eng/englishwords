import XCTest
@testable import EnglishWords

final class SmokeAutoTests: XCTestCase {
    func testCredentialsAreUnavailableWhenAnyRequiredEnvironmentValueIsMissing() {
        XCTAssertNil(SmokeAuto.credentials(environment: ["SMOKE_AUTO": "1"]))
        XCTAssertNil(SmokeAuto.credentials(environment: [
            "SMOKE_AUTO": "1",
            "SMOKE_PHONE": "19900000000",
        ]))
        XCTAssertNil(SmokeAuto.credentials(environment: [
            "SMOKE_AUTO": "1",
            "SMOKE_PASSWORD": "injected-secret",
        ]))
    }

    func testCredentialsComeOnlyFromCompleteEnvironmentInjection() throws {
        let credentials = try XCTUnwrap(SmokeAuto.credentials(environment: [
            "SMOKE_AUTO": "1",
            "SMOKE_PHONE": "19900000000",
            "SMOKE_PASSWORD": "injected-secret",
        ]))

        XCTAssertEqual(credentials.phone, "19900000000")
        XCTAssertEqual(credentials.password, "injected-secret")
    }
}
