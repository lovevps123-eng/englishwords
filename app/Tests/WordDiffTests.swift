// WordDiffTests.swift — TDD：LCS 词级对齐，覆盖全对/漏词/乱序/空识别四种场景。
// 测的是 app 模块自己的 WordDiff.swift 副本（从 spike/Sources/WordDiff.swift 复制而来，
// spike 目录本身不动），配合 StrictScoring 验证得分计算。
import XCTest
@testable import EnglishWords

final class WordDiffTests: XCTestCase {
    // ① 全对：识别结果与目标句完全一致，每个词都命中，得分 100。
    func testAllWordsHitWhenRecognizedMatchesTarget() {
        let diff = WordDiff.diff(target: "the quick brown fox", recognized: "the quick brown fox")

        XCTAssertEqual(diff.map(\.word), ["the", "quick", "brown", "fox"])
        XCTAssertEqual(diff.map(\.hit), [true, true, true, true])
        XCTAssertEqual(StrictScoring().score(diff: diff), 100)
    }

    // ② 漏词：识别结果漏掉中间一个词，其余按序命中。
    func testMissingWordIsMarkedAsMiss() {
        let diff = WordDiff.diff(target: "the quick brown fox", recognized: "the brown fox")

        XCTAssertEqual(diff.map(\.word), ["the", "quick", "brown", "fox"])
        XCTAssertEqual(diff.map(\.hit), [true, false, true, true])
        XCTAssertEqual(StrictScoring().score(diff: diff), 75)
    }

    // ③ 乱序：识别结果包含所有词但顺序被打乱。LCS 只能沿顺序取最长公共子序列，
    // 因此仅有保持相对顺序的词（this/brown）算命中，被调换到"不可延续"位置的词（quick/fox）
    // 判为未命中——这是词级对齐算法对乱序的预期行为，不是漏检。
    func testOutOfOrderWordsBreakSequentialMatch() {
        let diff = WordDiff.diff(target: "the quick brown fox", recognized: "quick the fox brown")

        XCTAssertEqual(diff.map(\.word), ["the", "quick", "brown", "fox"])
        XCTAssertEqual(diff.map(\.hit), [true, false, true, false])
        XCTAssertEqual(StrictScoring().score(diff: diff), 50)
    }

    // ④ 空识别：识别结果为空字符串（如未开口/识别器无输出），所有词判为未命中，得分 0。
    func testEmptyRecognizedMarksAllWordsAsMiss() {
        let diff = WordDiff.diff(target: "the quick brown fox", recognized: "")

        XCTAssertEqual(diff.map(\.word), ["the", "quick", "brown", "fox"])
        XCTAssertEqual(diff.map(\.hit), [false, false, false, false])
        XCTAssertEqual(StrictScoring().score(diff: diff), 0)
    }
}
