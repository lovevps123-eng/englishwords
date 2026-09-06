import XCTest
@testable import EnglishWords

final class KeychainStoreLifecycleTests: XCTestCase {
    private var keychain: KeychainStore!

    override func setUp() {
        super.setUp()
        keychain = KeychainStore(service: "KeychainStoreLifecycleTests.\(UUID().uuidString)")
    }

    override func tearDown() {
        keychain.clear()
        keychain.clearDeletionReceipt()
        keychain = nil
        super.tearDown()
    }

    func testClearingLearningTokensPreservesDeletionReceipt() throws {
        XCTAssertTrue(keychain.saveTokens(access: "access", refresh: "refresh"))
        XCTAssertTrue(keychain.saveDeletionReceipt("receipt"))

        XCTAssertTrue(keychain.clear())

        XCTAssertNil(keychain.loadTokens())
        XCTAssertEqual(keychain.loadDeletionReceipt(), "receipt")
    }

    func testClearingDeletionReceiptPreservesLearningTokens() throws {
        XCTAssertTrue(keychain.saveTokens(access: "access", refresh: "refresh"))
        XCTAssertTrue(keychain.saveDeletionReceipt("receipt"))

        XCTAssertTrue(keychain.clearDeletionReceipt())

        XCTAssertNil(keychain.loadDeletionReceipt())
        XCTAssertEqual(keychain.loadTokens(), AuthTokens(access: "access", refresh: "refresh"))
    }
}
