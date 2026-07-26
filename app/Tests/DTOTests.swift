// DTOTests.swift — 用 spec 中的 JSON 样例断言 DTO 解码正确，含 snake_case 字段
import XCTest
@testable import EnglishWords

final class DTOTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testWordPayloadDecoding() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "word": "apple",
          "phonetic": "/ˈæpl/",
          "definitions": [
            {"pos": "n.", "meaning": "苹果", "example": "I eat an apple every day."}
          ],
          "examples": [
            {"en": "She ate an apple.", "cn": "她吃了一个苹果。", "source": "gaokao"}
          ],
          "stage": 2
        }
        """
        let word = try decode(WordPayload.self, json)
        XCTAssertEqual(word.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(word.word, "apple")
        XCTAssertEqual(word.phonetic, "/ˈæpl/")
        XCTAssertEqual(word.stage, 2)
        XCTAssertEqual(word.definitions.count, 1)
        XCTAssertEqual(word.definitions[0].pos, "n.")
        XCTAssertEqual(word.definitions[0].meaning, "苹果")
        XCTAssertEqual(word.definitions[0].example, "I eat an apple every day.")
        XCTAssertEqual(word.examples.count, 1)
        XCTAssertEqual(word.examples[0].en, "She ate an apple.")
        XCTAssertEqual(word.examples[0].cn, "她吃了一个苹果。")
        XCTAssertEqual(word.examples[0].source, "gaokao")
    }

    func testWordPayloadWithNullPhoneticAndNullExample() throws {
        let json = """
        {
          "id": "22222222-2222-2222-2222-222222222222",
          "word": "run",
          "phonetic": null,
          "definitions": [
            {"pos": "v.", "meaning": "跑", "example": null}
          ],
          "examples": [],
          "stage": 0
        }
        """
        let word = try decode(WordPayload.self, json)
        XCTAssertNil(word.phonetic)
        XCTAssertNil(word.definitions[0].example)
        XCTAssertTrue(word.examples.isEmpty)
    }

    func testQueueResponseDecoding() throws {
        let json = """
        {
          "new": [
            {"id": "1", "word": "apple", "phonetic": null, "definitions": [], "examples": [], "stage": 0}
          ],
          "review": [
            {"id": "2", "word": "banana", "phonetic": "/bəˈnænə/", "definitions": [], "examples": [], "stage": 3}
          ]
        }
        """
        let queue = try decode(QueueResponse.self, json)
        XCTAssertEqual(queue.new.count, 1)
        XCTAssertEqual(queue.new[0].word, "apple")
        XCTAssertEqual(queue.review.count, 1)
        XCTAssertEqual(queue.review[0].stage, 3)
    }

    func testStudyStatsDecodingSnakeCase() throws {
        let json = """
        {"learning": 12, "mastered": 5, "due_today": 3, "days_active": 7, "streak": 4}
        """
        let stats = try decode(StudyStats.self, json)
        XCTAssertEqual(stats.learning, 12)
        XCTAssertEqual(stats.mastered, 5)
        XCTAssertEqual(stats.dueToday, 3)
        XCTAssertEqual(stats.daysActive, 7)
        XCTAssertEqual(stats.streak, 4)
    }

    func testTokenResponseDecodingSnakeCase() throws {
        let json = """
        {"access_token": "abc.def.ghi", "refresh_token": "jkl.mno.pqr", "token_type": "bearer"}
        """
        let token = try decode(TokenResponse.self, json)
        XCTAssertEqual(token.accessToken, "abc.def.ghi")
        XCTAssertEqual(token.refreshToken, "jkl.mno.pqr")
        XCTAssertEqual(token.tokenType, "bearer")
    }

    func testLoginRequestEncodingUsesSnakeCaseAndOmitsNilTurnstile() throws {
        let req = LoginRequest(phone: "13800000000", password: "password1")
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["phone"] as? String, "13800000000")
        XCTAssertEqual(obj?["password"] as? String, "password1")
        XCTAssertNil(obj?["turnstile_token"])
    }
}
