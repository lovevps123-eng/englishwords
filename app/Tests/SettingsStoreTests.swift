import XCTest
import SwiftData
@testable import EnglishWords

private final class FailingReceiptClearStore: DeletionReceiptStoring {
    var record = DeletionReceiptRecord(
        receipt: "receipt", requestID: "request-1", accountSubject: "subject-1"
    )
    private(set) var clearCount = 0

    func saveDeletionReceiptRecord(_ record: DeletionReceiptRecord) -> Bool {
        self.record = record
        return true
    }

    func loadDeletionReceiptRecord() -> DeletionReceiptRecord? { record }

    func clearDeletionReceipt() -> Bool {
        clearCount += 1
        return false
    }
}

@MainActor
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

    func testConfirmedDeletionClearsAllAccountLocalData() throws {
        let keychain = KeychainStore(service: "SettingsStoreTests.\(UUID().uuidString)")
        XCTAssertTrue(keychain.saveTokens(access: "access", refresh: "refresh"))
        XCTAssertTrue(keychain.saveDeletionReceiptRecord(DeletionReceiptRecord(
            receipt: "receipt", requestID: "request-1", accountSubject: "subject-1"
        )))
        let authStore = AuthStore(keychain: keychain)
        let settings = SettingsStore(
            defaults: defaults,
            configuration: AppConfiguration(defaults: defaults, environment: .debug)
        )
        settings.tier = 2
        settings.dailyNewLimit = 90
        defaults.set(true, forKey: "checkin.speaking.2026-09-06")
        defaults.set(true, forKey: "checkin.reading.2026-09-06")
        defaults.set("keep", forKey: "unrelated")

        let container = try ModelContainer(
            for: Schema([CachedWord.self, PendingResult.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        context.insert(CachedWord(
            serverId: "word-1", word: "apple", phonetic: nil,
            definitionsJSON: "[]", examplesJSON: "[]", stage: 0, group: "new"
        ))
        context.insert(PendingResult(clientId: "result-1", wordId: "word-1", feedback: "know"))
        try context.save()
        let vocabStore = VocabStore(modelContext: context)
        let cleaner = LocalAccountDataCleaner(
            vocabStore: vocabStore,
            settingsStore: settings,
            authStore: authStore,
            receiptStore: keychain,
            defaults: defaults
        )

        try cleaner.clearAfterConfirmedDeletion()

        XCTAssertTrue(try context.fetch(FetchDescriptor<CachedWord>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingResult>()).isEmpty)
        XCTAssertNil(defaults.object(forKey: "checkin.speaking.2026-09-06"))
        XCTAssertNil(defaults.object(forKey: "checkin.reading.2026-09-06"))
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
        XCTAssertEqual(settings.tier, SettingsStore.tierDefault)
        XCTAssertEqual(settings.dailyNewLimit, SettingsStore.dailyNewLimitDefault)
        XCTAssertNil(defaults.object(forKey: SettingsStore.Keys.tier))
        XCTAssertNil(defaults.object(forKey: SettingsStore.Keys.dailyNewLimit))
        XCTAssertNil(keychain.loadTokens())
        XCTAssertNil(keychain.loadDeletionReceiptRecord())
        XCTAssertFalse(authStore.isAuthenticated)
    }

    func testConfirmedDeletionReportsReceiptClearFailureAndKeepsReceipt() throws {
        let keychain = KeychainStore(service: "SettingsStoreTests.\(UUID().uuidString)")
        let authStore = AuthStore(keychain: keychain)
        let settings = SettingsStore(
            defaults: defaults,
            configuration: AppConfiguration(defaults: defaults, environment: .debug)
        )
        let container = try ModelContainer(
            for: Schema([CachedWord.self, PendingResult.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let receiptStore = FailingReceiptClearStore()
        let record = receiptStore.record
        let cleaner = LocalAccountDataCleaner(
            vocabStore: VocabStore(modelContext: ModelContext(container)),
            settingsStore: settings,
            authStore: authStore,
            receiptStore: receiptStore,
            defaults: defaults
        )

        XCTAssertThrowsError(try cleaner.clearAfterConfirmedDeletion())
        XCTAssertEqual(receiptStore.clearCount, 1)
        XCTAssertEqual(receiptStore.record, record)
    }
}
