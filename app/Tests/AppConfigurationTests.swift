import XCTest
@testable import EnglishWords

final class AppConfigurationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppConfigurationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testReleaseAlwaysUsesProductionHTTPSURL() throws {
        defaults.set("https://staging.example.com", forKey: AppConfiguration.serverOverrideKey)
        let subject = AppConfiguration(defaults: defaults, environment: .release)
        XCTAssertEqual(subject.baseURL, URL(string: "https://senior.dafang-edu.com")!)
    }

    func testDebugAcceptsAndNormalizesHTTPSOverride() throws {
        let subject = AppConfiguration(defaults: defaults, environment: .debug)
        try subject.applyServerOverride("  https://staging.example.com///  ")
        XCTAssertEqual(subject.baseURL.absoluteString, "https://staging.example.com")
    }

    func testDebugPreservesNonRootPathWhileRemovingTrailingSlashes() throws {
        let subject = AppConfiguration(defaults: defaults, environment: .debug)
        try subject.applyServerOverride("https://staging.example.com/api///")
        XCTAssertEqual(subject.baseURL.absoluteString, "https://staging.example.com/api")
    }

    func testDebugAcceptsOnlyLocalHTTPHosts() throws {
        let subject = AppConfiguration(defaults: defaults, environment: .debug)
        for value in ["http://localhost:8000", "http://127.0.0.1:8000", "http://[::1]:8000"] {
            try subject.applyServerOverride(value)
            XCTAssertEqual(subject.baseURL.scheme, "http")
        }
        XCTAssertThrowsError(try subject.applyServerOverride("http://example.com")) { error in
            XCTAssertEqual(error as? ConfigurationError, .httpsRequired)
        }
    }

    func testRejectsCredentialsQueryAndFragment() throws {
        let subject = AppConfiguration(defaults: defaults, environment: .debug)
        let cases: [(String, ConfigurationError)] = [
            ("https://user:pass@example.com", .credentialsNotAllowed),
            ("https://example.com/path?foo=bar", .queryOrFragmentNotAllowed),
            ("https://example.com/path#fragment", .queryOrFragmentNotAllowed),
        ]
        for (value, expected) in cases {
            XCTAssertThrowsError(try subject.applyServerOverride(value)) { error in
                XCTAssertEqual(error as? ConfigurationError, expected)
            }
        }
    }

    func testInvalidApplyPreservesLastValidOverride() throws {
        let subject = AppConfiguration(defaults: defaults, environment: .debug)
        try subject.applyServerOverride("https://staging.example.com")
        XCTAssertThrowsError(try subject.applyServerOverride("http://example.com"))
        XCTAssertEqual(subject.storedOverride, "https://staging.example.com")
        XCTAssertEqual(subject.baseURL.absoluteString, "https://staging.example.com")
    }

    func testResetReturnsToProductionURL() throws {
        let subject = AppConfiguration(defaults: defaults, environment: .debug)
        try subject.applyServerOverride("https://staging.example.com")
        subject.resetServerOverride()
        XCTAssertNil(subject.storedOverride)
        XCTAssertEqual(subject.baseURL, AppConfiguration.productionBaseURL)
    }
}
