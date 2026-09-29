@testable import Vibeshed
import XCTest
import Yams

@MainActor
final class DefaultConfigTests: XCTestCase {
    /// The config for a Mac where none of the integrations' software turned up.
    private let bareMac = DefaultConfig.yaml(detected: [])

    func testPickerHotkeyParses() throws {
        let config = try ConfigManager.parseYAML(bareMac)
        XCTAssertEqual(config.keybindings.count, 1)
        let binding = try XCTUnwrap(config.keybindings.first)
        XCTAssertEqual(binding.action, "app/togglePicker")
        XCTAssertNoThrow(try KeyComboParser.parse(binding.combo))
        XCTAssertFalse(binding.usesCapsLock, "Caps Lock would need Input Monitoring")
    }

    func testLeavesDefaultBrowserAlone() throws {
        let config = try ConfigManager.parseYAML(bareMac)
        XCTAssertFalse(config.urlRouting.registerAsDefaultBrowser)
    }

    /// Window, clipboard and theme join the modules that work with macOS alone.
    func testEnablesBuiltInModulesOnEveryMac() throws {
        let config = try ConfigManager.parseYAML(bareMac)
        XCTAssertEqual(
            Set(config.moduleConfigs.keys),
            [
                "application", "system", "settings", "audio", "processes", "performance", "window", "clipboard",
                "theme", "math", "timer", "emoji", "websearch", "self",
            ]
        )
    }

    func testEnablesAModuleForEachDetectedIntegration() throws {
        let detected = SoftwareIntegration.detect(in: SoftwareEnvironment(
            isAppInstalled: { $0 == "com.spotify.client" },
            fileExists: { $0 == "/usr/local/bin/brew" },
            homeDirectory: "/Users/test"
        ))
        let config = try ConfigManager.parseYAML(DefaultConfig.yaml(detected: detected))
        let modules = Set(config.moduleConfigs.keys)
        XCTAssertTrue(modules.isSuperset(of: ["spotify", "homebrew"]))
        XCTAssertFalse(modules.contains("iterm"))

        let homebrew = try YAMLDecoder().decode(
            HomebrewConfig.self,
            from: XCTUnwrap(config.moduleConfigs["homebrew"])
        )
        XCTAssertEqual(homebrew.brewPath, "/usr/local/bin/brew")
    }

    /// Everything that isn't enabled is listed commented out, ready to uncomment.
    func testListsEveryOtherModuleCommentedOut() throws {
        let listed = DefaultConfig.optionalModules.map(\.moduleID) + SoftwareIntegration.all.map(\.moduleID)
        for moduleID in listed {
            XCTAssertTrue(bareMac.contains("\n  # \(moduleID):"), "\(moduleID) isn't listed")
        }
        let uncommented = bareMac.replacingOccurrences(of: "\n  # ", with: "\n  ")
        let config = try ConfigManager.parseYAML(uncommented)
        XCTAssertTrue(Set(config.moduleConfigs.keys).isSuperset(of: listed))
    }

    /// Every section is empty, so each module runs on its `defaultConfig`.
    func testBuiltInModulesHaveValidDefaults() {
        assertValidDefaults(ApplicationModule.self)
        assertValidDefaults(SystemModule.self)
        assertValidDefaults(SettingsModule.self)
        assertValidDefaults(AudioModule.self)
        assertValidDefaults(ProcessesModule.self)
        assertValidDefaults(PerformanceModule.self)
        assertValidDefaults(WindowModule.self)
        assertValidDefaults(ClipboardModule.self)
        assertValidDefaults(ThemeModule.self)
        assertValidDefaults(MathModule.self)
        assertValidDefaults(TimerModule.self)
        assertValidDefaults(EmojiModule.self)
        assertValidDefaults(WebSearchModule.self)
        assertValidDefaults(SelfModule.self)
    }

    /// The IDs the config lists are the ones the modules answer to.
    func testListsRealModules() async {
        let modules: [any Module] = [
            ApplicationModule(), SystemModule(), SettingsModule(), AudioModule(), ProcessesModule(),
            PerformanceModule(), WindowModule(), ClipboardModule(), ThemeModule(), MathModule(), TimerModule(),
            EmojiModule(), WebSearchModule(), TilingModule(), MenuModule(), BookmarkModule(), CalendarModule(),
            MeetingPrepModule(),
        ]
        var ids: Set<String> = []
        for module in modules {
            await ids.insert(module.id)
        }
        // SelfModule needs the app's callbacks to build; its ID is fixed.
        let listed = (DefaultConfig.builtInModules + DefaultConfig.optionalModules).map(\.moduleID)
        XCTAssertEqual(ids.union(["self"]), Set(listed))
    }

    private func assertValidDefaults<M: ModuleConfigurable>(
        _ module: M.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let defaults = M.defaultConfig else {
            return XCTFail("\(M.self) has no defaultConfig", file: file, line: line)
        }
        XCTAssertTrue(M.validate(defaults).isValid, "\(M.self) defaults invalid", file: file, line: line)
    }
}
