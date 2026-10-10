@testable import Vibeshed
import XCTest

final class EmojiModuleTests: XCTestCase {
    private let scoring = ScoringContext(
        usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
    )
    private let find = ActionID(module: "emoji", name: "find")

    func testCatalogParsesGeneratedData() {
        XCTAssertGreaterThan(EmojiCatalog.entries.count, 1000)
        XCTAssertTrue(EmojiCatalog.entries.contains { $0.char == "🤷" })
        // Every entry has a char and a name.
        XCTAssertTrue(EmojiCatalog.entries.allSatisfy { !$0.char.isEmpty && !$0.name.isEmpty })
    }

    func testOnlyFindActionIsTopLevel() async {
        let module = EmojiModule()
        let actions = await module.provideActions(query: "shrug", scoring: scoring)
        XCTAssertEqual(actions.map(\.id), [find])
    }

    func testFindOptionsAreTheWholeCatalogInOrder() async {
        let module = EmojiModule()
        let options = await module.provideParameterOptions(for: "emoji", in: find, query: "")
        XCTAssertEqual(options.map(\.id), EmojiCatalog.entries.map(\.char))
    }

    func testPickerFindsEmojiByKeyword() async {
        let module = EmojiModule()
        let options = await module.provideParameterOptions(for: "emoji", in: find, query: "car")
        // 🚗's name is "automobile" — only its "car" keyword matches.
        let top = options.fuzzyFiltered(by: "car").prefix(8).map(\.id)
        XCTAssertTrue(top.contains("🚗"), "got \(top)")
    }

    /// Pasting types into the user's app, so a Shift run must not keep the picker focused.
    func testActionsTypeIntoFrontmostAppOnlyWhenPasting() async {
        let module = EmojiModule()
        let copyID = ActionID(module: "emoji", name: "copy.person-shrugging")
        for pasteOnSelect in [false, true] {
            var config = EmojiConfig()
            config.pasteOnSelect = pasteOnSelect
            await module.configDidUpdate(config)
            let findAction = await module.action(id: find)
            let copyAction = await module.action(id: copyID)
            XCTAssertEqual(findAction?.typesIntoFrontmostApp, pasteOnSelect)
            XCTAssertEqual(copyAction?.typesIntoFrontmostApp, pasteOnSelect)
        }
    }

    func testActionsResolvableByID() async {
        let module = EmojiModule()
        let copy = await module.action(id: ActionID(module: "emoji", name: "copy.person-shrugging"))
        XCTAssertNotNil(copy, "emoji IDs must resolve for keybindings/URIs")
        XCTAssertTrue(copy?.title.contains("🤷") ?? false)
        let findAction = await module.action(id: find)
        XCTAssertNotNil(findAction)
    }
}
