@testable import Vibeshed
import XCTest
import Yams

/// A config section may set only what it changes; the rest keeps its default instead of
/// the whole section failing to decode (which `ModuleConfigDecoder` answers by quietly
/// running the module on its defaults).
final class PartialConfigDecodingTests: XCTestCase {
    func testWindowSectionWithOnlyPadding() throws {
        let config = try YAMLDecoder().decode(WindowConfig.self, from: "padding: { top: 4, gap: 4 }")
        XCTAssertEqual(config.padding, PaddingConfig(top: 4, gap: 4))
        XCTAssertEqual(config.horizontalStops, WindowConfig.defaultValue.horizontalStops)
        XCTAssertEqual(config.verticalStops, WindowConfig.defaultValue.verticalStops)
        XCTAssertEqual(config.enlargeShrinkStep, WindowConfig.defaultValue.enlargeShrinkStep)
        XCTAssertFalse(config.includeMinimized)
    }

    func testTilingSectionWithOnlyAGrid() throws {
        let yaml = """
        defaultGrid:
          columns: [1, 1]
          rows: [1]
        """
        let config = try YAMLDecoder().decode(TilingConfig.self, from: yaml)
        XCTAssertEqual(config.defaultGrid?.columns, [1, 1])
        XCTAssertEqual(config.defaultGrid?.rows, [1])
        XCTAssertEqual(config.displays, [])
        XCTAssertEqual(config.padding, PaddingConfig())
        XCTAssertEqual(config.autoTile, AutoTileConfig())
    }

    /// Only an empty section gets the default 2×2 grid; one that sets other keys and
    /// leaves `defaultGrid` out has none, as before.
    func testTilingSectionWithoutGridKeepsNoGrid() throws {
        let config = try YAMLDecoder().decode(TilingConfig.self, from: "padding: { gap: 8 }")
        XCTAssertNil(config.defaultGrid)
        XCTAssertEqual(config.padding.gap, 8)
    }

    // MARK: - The sections from the 0.6.1 log

    /// Each failed with keyNotFound for a key it left out, so these settings were ignored.
    func testReportedSectionsKeepWhatTheySet() throws {
        XCTAssertEqual(
            try YAMLDecoder().decode(
                ApplicationConfig.self,
                from: "{ showRunningOnly: false, excludedBundleIDs: [com.apple.Dock] }"
            ),
            ApplicationConfig(excludedBundleIDs: ["com.apple.Dock"])
        )
        XCTAssertEqual(
            try YAMLDecoder().decode(ClipboardConfig.self, from: "{ maxItems: 50, pasteOnSelect: false }"),
            ClipboardConfig(maxItems: 50, pasteOnSelect: false)
        )
        XCTAssertEqual(
            try YAMLDecoder().decode(MathConfig.self, from: "{ enableCurrency: false }"),
            MathConfig(enableCurrency: false)
        )
        XCTAssertEqual(
            try YAMLDecoder().decode(SystemConfig.self, from: "{ enabledActions: [lock, sleep] }"),
            SystemConfig(enabledActions: ["lock", "sleep"])
        )
    }

    // MARK: - One key per config

    func testModuleSectionsWithASingleKey() throws {
        try assertDecodes("cacheTTLSeconds: 10", as: ApplicationConfig(cacheTTLSeconds: 10))
        try assertDecodes("volumeStep: 5", as: AudioConfig(volumeStep: 5))
        try assertDecodes("showMostVisited: false", as: BookmarkConfig(showMostVisited: false))
        try assertDecodes("maxResults: 50", as: BrowserConfig(maxResults: 50))
        try assertDecodes("showAllDayEvents: true", as: CalendarConfig(showAllDayEvents: true))
        try assertDecodes("pollingInterval: 2", as: ClipboardConfig(pollingInterval: 2))
        try assertDecodes("token: ghp_x", as: GitHubConfig(token: "ghp_x"))
        try assertDecodes("enabledActions: [update]", as: HomebrewConfig(enabledActions: ["update"]))
        try assertDecodes("showJobName: false", as: ITermConfig(showJobName: false))
        try assertDecodes("openInNewWindow: true", as: JetBrainsConfig(openInNewWindow: true))
        try assertDecodes("decimalPlaces: 2", as: MathConfig(decimalPlaces: 2))
        try assertDecodes("autoJoinVideo: true", as: MeetingPrepConfig(autoJoinVideo: true))
        try assertDecodes("excludedNames: [kernel_task]", as: ProcessesConfig(excludedNames: ["kernel_task"]))
        try assertDecodes("clientId: abc", as: SpotifyConfig(clientId: "abc"))
        try assertDecodes("screenshotPath: ~/Screenshots", as: SystemConfig(screenshotPath: "~/Screenshots"))
        try assertDecodes("showSavedMessages: false", as: TelegramConfig(showSavedMessages: false))
        try assertDecodes("defaultSound: Ping", as: TimerConfig(defaultSound: "Ping"))
        try assertDecodes("showFiles: true", as: VSCodeConfig(showFiles: true))
        try assertDecodes("showRemote: true", as: ZedConfig(showRemote: true))
        try assertDecodes("personalMeetingId: \"123\"", as: ZoomConfig(personalMeetingId: "123"))
    }

    func testListEntriesNeedOnlyTheirName() throws {
        try assertDecodes(
            "chats: [{ name: Mom, username: mom }]",
            as: TelegramConfig(chats: [TelegramChatEntry(name: "Mom", username: "mom")])
        )
        try assertDecodes(
            "meetings: [{ name: Standup, link: \"https://zoom.us/j/1\" }]",
            as: ZoomConfig(meetings: [ZoomMeetingEntry(name: "Standup", link: "https://zoom.us/j/1")])
        )
    }

    // MARK: - Top-level sections

    func testURLRoutingSectionWithOnlyADefaultBrowser() throws {
        try assertDecodes("defaultBrowser: firefox", as: URLRoutingConfig(defaultBrowser: "firefox"))
        try assertDecodes("registerAsDefaultBrowser: false", as: URLRoutingConfig(registerAsDefaultBrowser: false))
    }

    func testEmptyLayoutCorrectionSectionStaysEnabled() throws {
        try assertDecodes("{}", as: AppConfig.LayoutCorrectionConfig())
        try assertDecodes("enabled: false", as: AppConfig.LayoutCorrectionConfig(enabled: false))
    }

    func testAppearanceSectionWithOnlyAWidth() throws {
        try assertDecodes("panelWidth: 900", as: AppConfig.AppearanceConfig(panelWidth: 900))
    }

    /// Through `ConfigManager`, which replaces a section it can't decode with the defaults.
    @MainActor
    func testPartialTopLevelSectionsSurviveParsing() throws {
        let config = try ConfigManager.parseYAML("""
        urlRouting:
          defaultBrowser: firefox
        layoutCorrection: {}
        appearance:
          panelWidth: 900
        """)
        XCTAssertEqual(config.urlRouting.defaultBrowser, "firefox")
        XCTAssertTrue(config.urlRouting.registerAsDefaultBrowser)
        XCTAssertTrue(config.layoutCorrection.enabled)
        XCTAssertEqual(config.appearance.panelWidth, 900)
        XCTAssertEqual(config.appearance.panelHeight, AppConfig.AppearanceConfig().panelHeight)
    }

    // MARK: - Helpers

    private func assertDecodes<C: Decodable & Equatable>(
        _ yaml: String,
        as expected: C,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(try YAMLDecoder().decode(C.self, from: yaml), expected, yaml, file: file, line: line)
    }
}
