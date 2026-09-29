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

    // MARK: - Module

    private let scoring = ScoringContext(
        usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
    )

    func testOnlyFindActionIsTopLevel() async {
        let module = EmojiModule()
        let actions = await module.provideActions(query: "shrug", scoring: scoring)
        XCTAssertEqual(actions.map(\.id), [ActionID(module: "emoji", name: "find")])
        XCTAssertEqual(actions.first?.parameters.first?.filtersOwnOptions, true)
    }

    func testFindOptionsMatchKeywords() async {
        let module = EmojiModule()
        let find = ActionID(module: "emoji", name: "find")
        let shrug = await module.provideParameterOptions(for: "emoji", in: find, query: "shrug")
        XCTAssertTrue(shrug.contains { $0.id == "🤷" })
        // "cheerful" is only a keyword of 😀, never part of its name.
        let cheerful = await module.provideParameterOptions(for: "emoji", in: find, query: "cheerful")
        XCTAssertTrue(cheerful.contains { $0.id == "😀" })
    }

    func testFindOptionsWithEmptyQueryAreCapped() async {
        let module = EmojiModule()
        let find = ActionID(module: "emoji", name: "find")
        let options = await module.provideParameterOptions(for: "emoji", in: find, query: "")
        XCTAssertEqual(options.count, EmojiConfig().maxResults)
        XCTAssertEqual(options.first?.id, EmojiCatalog.entries.first?.char)
    }

    func testActionsResolvableByID() async {
        let module = EmojiModule()
        let copy = await module.action(id: ActionID(module: "emoji", name: "copy.person-shrugging"))
        XCTAssertNotNil(copy, "emoji IDs must resolve for keybindings/URIs")
        XCTAssertTrue(copy?.title.contains("🤷") ?? false)
        let find = await module.action(id: ActionID(module: "emoji", name: "find"))
        XCTAssertNotNil(find)
    }
}
