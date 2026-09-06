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
        let record = DeletionReceiptRecord(
            receipt: "receipt", requestID: "request-1", accountSubject: "subject-1"
        )
        XCTAssertTrue(keychain.saveDeletionReceiptRecord(record))

        XCTAssertTrue(keychain.clear())

        XCTAssertNil(keychain.loadTokens())
        XCTAssertEqual(keychain.loadDeletionReceiptRecord(), record)
    }

    func testClearingDeletionReceiptPreservesLearningTokens() throws {
        XCTAssertTrue(keychain.saveTokens(access: "access", refresh: "refresh"))
        XCTAssertTrue(keychain.saveDeletionReceiptRecord(DeletionReceiptRecord(
            receipt: "receipt", requestID: "request-1", accountSubject: "subject-1"
        )))

        XCTAssertTrue(keychain.clearDeletionReceipt())

        XCTAssertNil(keychain.loadDeletionReceiptRecord())
        XCTAssertEqual(keychain.loadTokens(), AuthTokens(access: "access", refresh: "refresh"))
    }
}
