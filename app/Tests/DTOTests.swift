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

    // MARK: - Reading

    func testArticleListResponseDecodingSnakeCase() throws {
        let json = """
        {
          "items": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "source": "bbc",
              "title": "How AI changes classrooms",
              "title_cn": "AI 如何改变课堂",
              "summary": "一篇关于 AI 教育的短文",
              "difficulty": "intermediate",
              "category": "tech",
              "word_count": 420,
              "published_at": "2026-07-20T08:00:00+00:00"
            }
          ],
          "total": 1,
          "page": 1,
          "pages": 1
        }
        """
        let response = try decode(ArticleListResponse.self, json)
        XCTAssertEqual(response.total, 1)
        XCTAssertEqual(response.page, 1)
        XCTAssertEqual(response.pages, 1)
        XCTAssertEqual(response.items.count, 1)
        let item = response.items[0]
        XCTAssertEqual(item.id, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(item.titleCn, "AI 如何改变课堂")
        XCTAssertEqual(item.difficulty, "intermediate")
        XCTAssertEqual(item.wordCount, 420)
        XCTAssertEqual(item.publishedAt, "2026-07-20T08:00:00+00:00")
    }

    func testArticleListItemDecodingWithNullOptionalFields() throws {
        let json = """
        {
          "id": "2", "source": "npr", "title": "t", "title_cn": null,
          "summary": null, "difficulty": "advanced", "category": "science",
          "word_count": 0, "published_at": null
        }
        """
        let item = try decode(ArticleSummary.self, json)
        XCTAssertNil(item.titleCn)
        XCTAssertNil(item.summary)
        XCTAssertNil(item.publishedAt)
    }

    func testArticleDetailDecodingWithVocabulary() throws {
        let json = """
        {
          "id": "1", "source": "bbc", "source_url": "https://example.com/a",
          "title": "Title", "title_cn": "标题",
          "content": "First paragraph.\\n\\nSecond paragraph.",
          "content_cn": "第一段。\\n\\n第二段。",
          "summary": "摘要",
          "vocabulary": [
            {"word": "classroom", "phonetic": "/ˈklæsruːm/", "meaning": "n. 教室",
             "examples": ["The classroom was empty.", "造句。"], "synonyms": "room", "note": "常考词"}
          ],
          "difficulty": "intermediate", "category": "tech", "word_count": 100,
          "published_at": "2026-07-20T08:00:00+00:00"
        }
        """
        let detail = try decode(ArticleDetail.self, json)
        XCTAssertEqual(detail.sourceUrl, "https://example.com/a")
        XCTAssertEqual(detail.content.components(separatedBy: "\n\n").count, 2)
        XCTAssertEqual(detail.contentCn?.components(separatedBy: "\n\n").count, 2)
        XCTAssertEqual(detail.vocabulary?.count, 1)
        XCTAssertEqual(detail.vocabulary?.first?.word, "classroom")
        XCTAssertEqual(detail.vocabulary?.first?.examples?.count, 2)
    }

    func testArticleDetailDecodingToleratesMalformedVocabulary() throws {
        // vocabulary 里的条目缺少必需的 "word" 字段——整体解码不应因此失败，vocabulary 兜底为 nil。
        let json = """
        {
          "id": "1", "source": "bbc", "source_url": "https://example.com/a",
          "title": "Title", "title_cn": null,
          "content": "Only paragraph.", "content_cn": null, "summary": null,
          "vocabulary": [{"phonetic": "/x/"}],
          "difficulty": "beginner", "category": "general", "word_count": 10,
          "published_at": null
        }
        """
        let detail = try decode(ArticleDetail.self, json)
        XCTAssertNil(detail.vocabulary, "缺少 word 字段的条目应让 vocabulary 整体兜底为 nil，而不是抛出解码错误")
        XCTAssertEqual(detail.content, "Only paragraph.")
    }

    func testArticleDetailDecodingWithNullVocabulary() throws {
        let json = """
        {
          "id": "1", "source": "bbc", "source_url": "https://example.com/a",
          "title": "Title", "title_cn": null,
          "content": "Only paragraph.", "content_cn": null, "summary": null,
          "vocabulary": null,
          "difficulty": "beginner", "category": "general", "word_count": 10,
          "published_at": null
        }
        """
        let detail = try decode(ArticleDetail.self, json)
        XCTAssertNil(detail.vocabulary)
    }

    func testCollectWordResponseDecodingSnakeCase() throws {
        let json = """
        {"status": "collected", "word_id": "abc-123"}
        """
        let response = try decode(CollectWordResponse.self, json)
        XCTAssertEqual(response.status, "collected")
        XCTAssertEqual(response.wordId, "abc-123")
    }

    func testCollectWordRequestEncoding() throws {
        let req = CollectWordRequest(word: "apple")
        let data = try JSONEncoder().encode(req)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["word"] as? String, "apple")
    }

    // MARK: - tokenizeArticleParagraph

    func testTokenizeArticleParagraphSplitsWordsAndStripsPunctuation() {
        let tokens = tokenizeArticleParagraph("Hello, world! It's a test-case.")
        XCTAssertEqual(tokens.map(\.display), ["Hello,", "world!", "It's", "a", "test-case."])
        XCTAssertEqual(tokens.map(\.normalized), ["hello", "world", "it's", "a", "test-case"])
    }

    func testTokenizeArticleParagraphPunctuationOnlyTokenNormalizesToEmpty() {
        let tokens = tokenizeArticleParagraph("word — word")
        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(tokens[1].display, "—")
        XCTAssertTrue(tokens[1].normalized.isEmpty, "纯标点 token 的 normalized 应为空串，调用方应跳过收藏")
    }

    // 真实抓取文章（html.unescape 还原）里的撇号普遍是 Unicode 弯引号 U+2019，而不是 ASCII 直引号。
    // 回归：弯引号版本的 "Don't" 应和直引号版本一样 normalize 成 "don't"，不能被误分词成 "dont"。
    func testTokenizeArticleParagraphNormalizesCurlyApostropheToStraight() {
        let tokens = tokenizeArticleParagraph("He said, \u{201C}Don\u{2019}t worry.\u{201D}")
        let dontToken = tokens.first { $0.display.contains("Don") }
        XCTAssertEqual(dontToken?.normalized, "don't")
    }

    func testTokenizeArticleParagraphNormalizesLeftCurlyApostropheToo() {
        // U+2018（左单引号）理论上不该出现在撇号位置，但同样归一，避免遗漏。
        let tokens = tokenizeArticleParagraph("rock \u{2018}n\u{2018} roll")
        XCTAssertEqual(tokens[1].normalized, "'n'")
    }
}
