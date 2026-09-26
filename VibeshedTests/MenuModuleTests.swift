import Carbon.HIToolbox
import Foundation
@testable import Vibeshed
import XCTest

/// Covers the pieces of the menu module that don't need a live app: path IDs,
/// shortcut labels, config decoding, and ID resolution.
final class MenuModuleTests: XCTestCase {
    // MARK: - Paths

    func testPathKeyRoundTrips() {
        let path = ["View", "Text Encoding", "Unicode (UTF-8)"]
        XCTAssertEqual(MenuPath.key(path), "View > Text Encoding > Unicode (UTF-8)")
        XCTAssertEqual(MenuPath.parse(MenuPath.key(path)), path)
    }

    func testParseKeepsSlashesInTitles() {
        XCTAssertEqual(MenuPath.parse("View > Show/Hide Sidebar"), ["View", "Show/Hide Sidebar"])
    }

    func testParseRejectsAnythingButAnItemInAMenu() {
        XCTAssertNil(MenuPath.parse("search"))
        XCTAssertNil(MenuPath.parse("File > "))
        XCTAssertNil(MenuPath.parse(" > New Tab"))
    }

    func testNormalizedTitleIgnoresCaseAndEllipsis() {
        XCTAssertEqual(MenuPath.normalized("Save As…"), "save as")
        XCTAssertEqual(MenuPath.normalized("save as..."), "save as")
        XCTAssertEqual(MenuPath.normalized("SAVE AS"), "save as")
    }

    func testEntrySubtitleShowsLocationAndShortcut() {
        let plain = MenuItemEntry(path: ["View", "Text Encoding", "Default"], shortcut: nil, isChecked: true)
        XCTAssertEqual(plain.title, "Default")
        XCTAssertEqual(plain.subtitle, "View › Text Encoding")

        let withShortcut = MenuItemEntry(path: ["File", "New Tab"], shortcut: "⌘T", isChecked: false)
        XCTAssertEqual(withShortcut.subtitle, "File · ⌘T")
    }

    // MARK: - Shortcuts

    func testCommandIsImpliedUnlessNoCommandIsSet() {
        XCTAssertEqual(MenuShortcut.format(character: "t", virtualKey: nil, modifiers: 0), "⌘T")
        XCTAssertEqual(MenuShortcut.format(character: "T", virtualKey: nil, modifiers: 1), "⇧⌘T")
        XCTAssertEqual(MenuShortcut.format(character: "W", virtualKey: nil, modifiers: 8), "W")
    }

    func testSpecialKeysUseTheirVirtualKeyCode() {
        // Force Quit: ⌥⇧⌘⎋ reported as char "⎋", virtual key 53.
        XCTAssertEqual(
            MenuShortcut.format(character: "⎋", virtualKey: Int(kVK_Escape), modifiers: 3),
            "⌥⇧⌘⎋"
        )
        // Delete reports a control character alongside its key code.
        XCTAssertEqual(MenuShortcut.format(character: "\u{08}", virtualKey: Int(kVK_Delete), modifiers: 0), "⌘⌫")
    }

    func testFunctionModifierPrefixesFn() {
        // Window › Move & Resize › Left: fn⌃← with no ⌘ (modifiers 16 | 8 | 4).
        XCTAssertEqual(
            MenuShortcut.format(character: nil, virtualKey: Int(kVK_LeftArrow), modifiers: 28),
            "fn⌃←"
        )
    }

    func testNoKeyMeansNoShortcut() {
        XCTAssertNil(MenuShortcut.format(character: nil, virtualKey: nil, modifiers: 0))
        XCTAssertNil(MenuShortcut.format(character: "", virtualKey: nil, modifiers: 2))
        XCTAssertNil(MenuShortcut.format(character: "\u{08}", virtualKey: nil, modifiers: 0))
    }

    // MARK: - Config

    /// A partial section must keep the defaults for the keys it leaves out; synthesized
    /// Decodable would throw and `ModuleConfigDecoder` would discard the whole section.
    func testConfigDecodesFromPartialSection() throws {
        let config = try JSONDecoder().decode(MenuConfig.self, from: Data(#"{"showInSearch": false}"#.utf8))
        XCTAssertFalse(config.showInSearch)
        XCTAssertEqual(config.maxSubmenuItems, 100)
        XCTAssertEqual(config.cacheTTLSeconds, 3.0)
        XCTAssertEqual(config.excludedBundleIDs, [])
    }

    func testValidateRejectsOutOfRangeValues() {
        var config = MenuConfig()
        XCTAssertTrue(MenuModule.validate(config).isValid)
        config.maxSubmenuItems = 0
        config.cacheTTLSeconds = -1
        XCTAssertEqual(MenuModule.validate(config).errors.count, 2)
    }

    // MARK: - ID resolution

    func testPathIDResolvesWithoutReadingMenus() async throws {
        let resolved = await MenuModule().action(id: ActionID("menu/File > New Tab"))
        let action = try XCTUnwrap(resolved)
        XCTAssertEqual(action.id.rawValue, "menu/File > New Tab")
        XCTAssertEqual(action.title, "New Tab")
        XCTAssertEqual(action.subtitle, "File")
        XCTAssertTrue(action.parameters.isEmpty)
    }

    func testSearchIDResolvesToParameterizedAction() async throws {
        let resolved = await MenuModule().action(id: ActionID("menu/search"))
        let action = try XCTUnwrap(resolved)
        XCTAssertEqual(action.parameters.map(\.id), ["item"])
        XCTAssertTrue(action.parameters.allSatisfy(\.isRequired))
    }

    func testItemKeywordsCoverTitleAndItsWords() {
        XCTAssertEqual(MenuModule.keywords(for: "Save As…"), ["save as…", "save", "as"])
    }

    /// An exact title match must outrank the web-search fallback, which carries the
    /// query itself as a keyword.
    func testExactTitleMatchOutranksWebSearchFallback() async {
        let item = MenuModule.itemAction(
            for: MenuItemEntry(path: ["View", "Basic"], shortcut: "⌘1", isChecked: true),
            listedFrom: nil
        )
        let scoring = ScoringContext(usageCounts: [:], lastUsedDates: [:], query: "basic", systemContext: nil)
        let fallbacks = await WebSearchModule().provideActions(query: "basic", scoring: scoring)
        XCTAssertFalse(fallbacks.isEmpty)

        let (ranked, _) = ActionScorer.scoreAndRank(
            allActions: fallbacks + [item],
            enrichments: [:],
            query: "basic",
            scoring: scoring
        )
        XCTAssertEqual(ranked.first?.id, item.id)
    }

    func testUnknownIDsDoNotResolve() async {
        let module = MenuModule()
        let unknown = await module.action(id: ActionID("menu/newTab"))
        let otherModule = await module.action(id: ActionID("window/File > New Tab"))
        XCTAssertNil(unknown)
        XCTAssertNil(otherModule)
    }
}
