import XCTest
@testable import EnglishWords

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testApplyingValidServerPersistsAndChangesEffectiveURL() throws {
        let configuration = AppConfiguration(defaults: defaults, environment: .debug)
        let settings = SettingsStore(defaults: defaults, configuration: configuration)

        try settings.applyServerBaseURL("https://staging.example.com")

        XCTAssertEqual(settings.serverBaseURL, "https://staging.example.com")
        XCTAssertEqual(configuration.baseURL, URL(string: "https://staging.example.com"))
    }

    func testApplyingInvalidServerPreservesPreviousValue() throws {
        let configuration = AppConfiguration(defaults: defaults, environment: .debug)
        let settings = SettingsStore(defaults: defaults, configuration: configuration)
        try settings.applyServerBaseURL("https://staging.example.com")

        XCTAssertThrowsError(try settings.applyServerBaseURL("http://example.com")) { error in
            XCTAssertEqual(error as? ConfigurationError, .httpsRequired)
        }

        XCTAssertEqual(settings.serverBaseURL, "https://staging.example.com")
        XCTAssertEqual(configuration.baseURL, URL(string: "https://staging.example.com"))
    }

    func testResetServerReturnsToProduction() throws {
        let configuration = AppConfiguration(defaults: defaults, environment: .debug)
        let settings = SettingsStore(defaults: defaults, configuration: configuration)
        try settings.applyServerBaseURL("https://staging.example.com")

        settings.resetServerBaseURL()

        XCTAssertEqual(settings.serverBaseURL, "")
        XCTAssertEqual(configuration.baseURL, AppConfiguration.productionBaseURL)
    }
}
