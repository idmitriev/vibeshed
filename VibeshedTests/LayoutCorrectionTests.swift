@testable import Vibeshed
import XCTest

final class LayoutCorrectionTests: XCTestCase {
    // MARK: - Keyboard layouts

    /// Apple's Russian layout, the letters only.
    private let russian: [Character: Character] = zip(
        "йцукенгшщзхъфывапролджэячсмитьбю", "qwertyuiop[]asdfghjkl;'zxcvbnm,."
    ).reduce(into: [:]) { $0[$1.0] = $1.1 }

    /// Apple's Ukrainian layout: shares most letters with Russian.
    private let ukrainian: [Character: Character] = zip(
        "йцукенгшщзхїфивапролджєячсмітьбю", "qwertyuiop[]asdfghjkl;'zxcvbnm,."
    ).reduce(into: [:]) { $0[$1.0] = $1.1 }

    func testMapsQueryWithTheLayoutThatCoversIt() {
        let result = LayoutTransliterator.bestMapping(
            for: "ыфафкш", tables: ["ru": russian, "uk": ukrainian], preferring: nil
        )
        XCTAssertEqual(result?.sourceID, "ru", "only Russian has ы")
        XCTAssertEqual(result?.corrected, "safari")
    }

    func testPrefersActiveLayoutWhenSeveralCoverQuery() {
        let tables = ["ru": russian, "uk": ukrainian]
        XCTAssertEqual(LayoutTransliterator.bestMapping(for: "сщву", tables: tables, preferring: "uk")?.sourceID, "uk")
        XCTAssertEqual(LayoutTransliterator.bestMapping(for: "сщву", tables: tables, preferring: "ru")?.sourceID, "ru")
    }

    func testCorrectsAfterSourceSwitchedBackToLatin() {
        // The active source is ABC now, but the query was typed in Russian.
        let result = LayoutTransliterator.bestMapping(for: "ыфафкш", tables: ["ru": russian], preferring: "abc")
        XCTAssertEqual(result?.corrected, "safari")
    }

    func testLeavesLatinAndUnknownScriptsAlone() {
        XCTAssertNil(LayoutTransliterator.bestMapping(for: "safari", tables: ["ru": russian], preferring: "ru"))
        XCTAssertNil(LayoutTransliterator.bestMapping(for: "café", tables: ["ru": russian], preferring: "ru"))
    }

    // MARK: - Korean

    func testKoreanDecomposesSyllablesToDubeolsikKeys() {
        XCTAssertEqual(InputMethodTransliteration.korean("ㅗ디ㅣㅐ"), "hello")
        XCTAssertEqual(InputMethodTransliteration.korean("ㄴㅁㄹㅁ갸"), "safari")
        XCTAssertEqual(InputMethodTransliteration.korean("ㅅㄷ그ㅑㅜ미"), "terminal")
        XCTAssertEqual(InputMethodTransliteration.korean("햐소ㅕㅠ"), "github")
    }

    func testKoreanSplitsCompoundVowelsAndFinals() {
        XCTAssertEqual(InputMethodTransliteration.korean("초개ㅡㄷ"), "chrome")
        XCTAssertEqual(InputMethodTransliteration.korean("뭐"), "anj", "ㅝ is ㅜ+ㅓ")
        XCTAssertEqual(InputMethodTransliteration.korean("닭"), "ekfr", "ㄺ is ㄹ+ㄱ")
        XCTAssertEqual(InputMethodTransliteration.korean("ㅆ"), "T", "doubled consonants are shifted keys")
    }

    func testKoreanIgnoresTextWithoutHangul() {
        XCTAssertNil(InputMethodTransliteration.korean("safari"))
    }

    // MARK: - Chinese (Zhuyin)

    func testZhuyinMapsBopomofoToKeys() {
        XCTAssertEqual(InputMethodTransliteration.zhuyin("ㄋㄇㄑㄇㄐㄛ"), "safari")
        XCTAssertEqual(InputMethodTransliteration.zhuyin("ㄔㄍㄐㄩㄛㄙㄇㄠ"), "terminal")
        XCTAssertNil(InputMethodTransliteration.zhuyin("ˇ"), "a tone mark alone isn't Zhuyin")
    }

    // MARK: - Japanese

    func testJapaneseReversesRomajiInput() {
        XCTAssertEqual(JapaneseRomaji.readings(of: "さふぁり").first, "safari")
        XCTAssertEqual(JapaneseRomaji.readings(of: "てｒみなｌ").first, "terminal")
        XCTAssertEqual(JapaneseRomaji.readings(of: "ｃｈろめ").first, "chrome")
        XCTAssertEqual(JapaneseRomaji.readings(of: "サファリ").first, "safari", "katakana mode")
    }

    func testJapaneseDoublesConsonantAfterSokuon() {
        XCTAssertEqual(JapaneseRomaji.readings(of: "あっｐ").first, "app")
        XCTAssertEqual(JapaneseRomaji.readings(of: "きって").first, "kitte")
    }

    func testJapaneseOffersAlternativeSpellings() {
        let readings = JapaneseRomaji.readings(of: "こで")
        XCTAssertEqual(readings, ["kode", "code"])
        XCTAssertTrue(JapaneseRomaji.readings(of: "しゃどw").contains("shadow"))
        XCTAssertTrue(JapaneseRomaji.readings(of: "ふｌｌ").contains("full"))
    }

    func testJapaneseDoublesNBeforeVowel() {
        XCTAssertEqual(JapaneseRomaji.readings(of: "あんあ").first, "anna")
        XCTAssertEqual(JapaneseRomaji.readings(of: "おんｌｙ").first, "only")
    }

    func testJapaneseCapsReadings() {
        XCTAssertLessThanOrEqual(JapaneseRomaji.readings(of: "しちつふじしちつふじ").count, JapaneseRomaji.maxReadings)
    }

    func testJapaneseIgnoresTextWithoutKana() {
        XCTAssertEqual(JapaneseRomaji.readings(of: "safari"), [])
        XCTAssertEqual(InputMethodTransliteration.candidates(for: "漢字"), [])
    }
}

// MARK: - Picker integration

/// Web search matches every query, so "no results" must mean no non-fallback
/// results — otherwise correction never runs once websearch is enabled.
@MainActor
final class LayoutCorrectionPickerTests: XCTestCase {
    private final class StubCorrector: LayoutCorrecting {
        let readings: [String: [String]]
        init(_ readings: [String: [String]]) {
            self.readings = readings
        }

        func corrections(for query: String) -> [LayoutCorrectionHint] {
            (readings[query] ?? []).map {
                LayoutCorrectionHint(originalQuery: query, correctedQuery: $0, sourceLayoutName: "Stub")
            }
        }
    }

    private func makeCoordinator(_ corrector: StubCorrector) async throws -> (PickerCoordinator, PickerState) {
        let eventBus = EventBus()
        let configManager = ConfigManager(eventBus: eventBus)
        let registry = ModuleRegistry(
            eventBus: eventBus,
            configManager: configManager,
            permissionsManager: PermissionsManager(eventBus: eventBus)
        )
        try await registry.register(MockModule())
        try await registry.register(CatchAllModule())
        let state = PickerState()
        let coordinator = PickerCoordinator(
            pickerState: state,
            moduleRegistry: registry,
            panelController: PanelController(pickerState: state, configManager: configManager),
            eventBus: eventBus
        )
        coordinator.layoutTransliterator = corrector
        return (coordinator, state)
    }

    func testCorrectsWhenOnlyFallbackMatches() async throws {
        let (coordinator, state) = try await makeCoordinator(StubCorrector(["скуфеу": ["create"], "сфдс": ["calc"]]))
        state.query = "сфдс"

        await coordinator.loadInitialActions().value

        XCTAssertEqual(state.layoutCorrectionHint?.correctedQuery, "calc")
        XCTAssertEqual(state.actions.first?.id, ActionID(module: "mock", name: "calculator"))
        XCTAssertEqual(state.actions.last?.title, "Search calc", "the catch-all searches the corrected text")
    }

    func testPicksTheReadingWithTheBestMatch() async throws {
        let (coordinator, state) = try await makeCoordinator(StubCorrector(["こで": ["zzzq", "calc"]]))
        state.query = "こで"

        await coordinator.loadInitialActions().value

        XCTAssertEqual(state.layoutCorrectionHint?.correctedQuery, "calc")
    }

    func testKeepsQueryWhenNoReadingMatches() async throws {
        let (coordinator, state) = try await makeCoordinator(StubCorrector(["яяя": ["zzzq"]]))
        state.query = "яяя"

        await coordinator.loadInitialActions().value

        XCTAssertNil(state.layoutCorrectionHint)
        XCTAssertEqual(state.actions.map(\.title), ["Search яяя"])
    }
}

/// Like web search: one fallback action for any non-empty query.
private actor CatchAllModule: Module {
    let id = "catchall"
    let displayName = "Catch-all"
    let iconName = "magnifyingglass"
    var isEnabled = true
    static let isQueryDependent = true

    func initialize(context _: ModuleContext) async throws {}

    func provideActions(query: String, scoring _: ScoringContext) async -> [any Action] {
        query.isEmpty ? [] : [CatchAllAction(query: query)]
    }
}

private struct CatchAllAction: Action {
    let query: String
    var id: ActionID {
        ActionID(module: "catchall", name: "search")
    }

    var title: String {
        "Search \(query)"
    }

    let subtitle = ""
    let iconName: String? = nil
    let isFallback = true
    let relevanceScore = 1.0
    var keywords: [String] {
        [query]
    }

    func run(with _: ParameterValues) async throws -> ActionResult {
        .dismiss
    }
}
