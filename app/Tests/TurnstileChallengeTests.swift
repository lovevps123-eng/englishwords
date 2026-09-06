import XCTest
@testable import EnglishWords

final class TurnstileChallengeTests: XCTestCase {
    private let productionBaseURL = URL(string: "https://senior.dafang-edu.com")!

    func testChallengeURLIsFixedUnderConfiguredHTTPSOrigin() throws {
        let validator = try TurnstileBridgeValidator(expectedBaseURL: productionBaseURL)

        XCTAssertEqual(
            validator.challengeURL,
            URL(string: "https://senior.dafang-edu.com/app-turnstile")!
        )
        XCTAssertTrue(validator.isAllowedNavigation(to: validator.challengeURL, isMainFrame: true))
        XCTAssertFalse(
            validator.isAllowedNavigation(
                to: URL(string: "https://senior.dafang-edu.com/app-turnstile?redirect=https://evil.example")!,
                isMainFrame: true
            )
        )
        XCTAssertFalse(
            validator.isAllowedNavigation(
                to: URL(string: "https://evil.example/app-turnstile")!,
                isMainFrame: true
            )
        )
    }

    func testValidMainFrameMessageReturnsBoundedToken() throws {
        let validator = try TurnstileBridgeValidator(expectedBaseURL: productionBaseURL)

        let token = validator.token(
            handlerName: "turnstile",
            sourceURL: validator.challengeURL,
            isMainFrame: true,
            body: ["type": "turnstile-token", "token": "short-lived-token"]
        )

        XCTAssertEqual(token, "short-lived-token")
    }

    func testRejectsWrongHandlerFrameOriginShapeAndTokenBounds() throws {
        let validator = try TurnstileBridgeValidator(expectedBaseURL: productionBaseURL)
        let validBody = ["type": "turnstile-token", "token": "short-lived-token"]

        XCTAssertNil(validator.token(
            handlerName: "callback", sourceURL: validator.challengeURL,
            isMainFrame: true, body: validBody
        ))
        XCTAssertNil(validator.token(
            handlerName: "turnstile", sourceURL: validator.challengeURL,
            isMainFrame: false, body: validBody
        ))
        XCTAssertNil(validator.token(
            handlerName: "turnstile", sourceURL: URL(string: "https://evil.example/app-turnstile"),
            isMainFrame: true, body: validBody
        ))
        XCTAssertNil(validator.token(
            handlerName: "turnstile", sourceURL: validator.challengeURL,
            isMainFrame: true, body: ["type": "unexpected", "token": "short-lived-token"]
        ))
        XCTAssertNil(validator.token(
            handlerName: "turnstile", sourceURL: validator.challengeURL,
            isMainFrame: true, body: ["type": "turnstile-token", "token": ""]
        ))
        XCTAssertNil(validator.token(
            handlerName: "turnstile", sourceURL: validator.challengeURL,
            isMainFrame: true,
            body: ["type": "turnstile-token", "token": String(repeating: "x", count: 4097)]
        ))
    }

    func testRejectsNonHTTPSConfiguredOrigin() {
        XCTAssertThrowsError(
            try TurnstileBridgeValidator(expectedBaseURL: URL(string: "http://localhost:8000")!)
        )
    }
}
