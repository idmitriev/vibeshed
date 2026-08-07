@testable import Vibeshed
import XCTest

final class EmojiModuleTests: XCTestCase {
    func testCatalogParsesGeneratedData() {
        XCTAssertGreaterThan(EmojiCatalog.entries.count, 1000)
        XCTAssertTrue(EmojiCatalog.entries.contains { $0.char == "🤷" })
        // Every entry has a char and a name.
        XCTAssertTrue(EmojiCatalog.entries.allSatisfy { !$0.char.isEmpty && !$0.name.isEmpty })
    }

    func testNamePrefixOutranksKeywordMatch() {
        let byName = EmojiEntry(char: "😀", name: "grinning face", keywords: ["happy"])
        let byKeyword = EmojiEntry(char: "🙂", name: "slightly smiling face", keywords: ["grin"])
        let nameScore = EmojiModule.matchScore(entry: byName, tokens: ["grin"])
        let keywordScore = EmojiModule.matchScore(entry: byKeyword, tokens: ["grin"])
        XCTAssertNotNil(nameScore)
        XCTAssertNotNil(keywordScore)
        XCTAssertGreaterThan(nameScore ?? 0, keywordScore ?? 0)
    }

    func testEveryTokenMustMatch() {
        let entry = EmojiEntry(char: "😀", name: "grinning face", keywords: ["happy"])
        XCTAssertNotNil(EmojiModule.matchScore(entry: entry, tokens: ["grinning", "face"]))
        XCTAssertNil(EmojiModule.matchScore(entry: entry, tokens: ["grinning", "zzz"]))
    }
}
