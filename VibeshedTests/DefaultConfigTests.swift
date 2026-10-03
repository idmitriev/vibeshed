@testable import Vibeshed
import XCTest
import Yams

@MainActor
final class DefaultConfigTests: XCTestCase {
    /// The config for a Mac where none of the integrations' software turned up.
    private let bareMac = DefaultConfig.yaml(detected: [])

    func testPickerHotkeyIsCapsLockSpace() throws {
        let config = try ConfigManager.parseYAML(bareMac)
        let binding = try XCTUnwrap(config.keybindings.first)
        XCTAssertEqual(binding.combo, "capslock+space")
        XCTAssertEqual(binding.action, "app/togglePicker")
        XCTAssertTrue(binding.usesCapsLock, "so permission setup asks for Input Monitoring")
    }

    func testWindowShortcuts() throws {
        let config = try ConfigManager.parseYAML(bareMac)
        let bindings = Dictionary(uniqueKeysWithValues: config.keybindings.map { ($0.combo, $0.action) })
        XCTAssertEqual(bindings, [
            "capslock+space": "app/togglePicker",
            "capslock+left": "window/focusLeft",
            "capslock+right": "window/focusRight",
            "capslock+up": "window/focusUp",
            "capslock+down": "window/focusDown",
            "capslock+m": "window/toggleMaximize",
            "capslock+p": "window/focusWindow",
            "capslock+w": "window/cycleTop",
            "capslock+a": "window/cycleLeft",
            "capslock+s": "window/cycleBottom",
            "capslock+d": "window/cycleRight",
        ])
        for binding in config.keybindings {
            XCTAssertNoThrow(try KeyComboParser.parse(binding.combo), binding.combo)
        }
    }

    /// Each shortcut runs an action the window module has (a typo would only show up
    /// as a log line at launch).
    func testWindowShortcutsNameRealActions() async throws {
        let config = try ConfigManager.parseYAML(bareMac)
        let actions = await WindowModule().provideActions(query: "", scoring: ScoringContext(
            usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
        ))
        let ids = Set(actions.map(\.id.rawValue))
        for action in config.keybindings.compactMap(\.action) where action != "app/togglePicker" {
            XCTAssertTrue(ids.contains(action), "\(action) doesn't exist")
        }
    }

    /// 4pt padding and gaps for both, and a two-column split for tiling.
    func testWindowAndTilingLayout() throws {
        let config = try ConfigManager.parseYAML(bareMac)
        let fourPoints = PaddingConfig(top: 4, bottom: 4, left: 4, right: 4, gap: 4)

        let window = try YAMLDecoder().decode(WindowConfig.self, from: XCTUnwrap(config.moduleConfigs["window"]))
        XCTAssertEqual(window.padding, fourPoints)
        XCTAssertEqual(window.horizontalStops, WindowConfig.defaultValue.horizontalStops)

        let tiling = try YAMLDecoder().decode(TilingConfig.self, from: XCTUnwrap(config.moduleConfigs["tiling"]))
        XCTAssertEqual(tiling.padding, fourPoints)
        XCTAssertEqual(tiling.defaultGrid?.columns, [1, 1])
        XCTAssertEqual(tiling.defaultGrid?.rows, [1])
        XCTAssertTrue(TilingModule.validate(tiling).isValid)
        XCTAssertTrue(WindowModule.validate(window).isValid)
    }

    func testLeavesDefaultBrowserAlone() throws {
        let config = try ConfigManager.parseYAML(bareMac)
        XCTAssertFalse(config.urlRouting.registerAsDefaultBrowser)
    }

    /// Window, tiling, clipboard and theme join the modules that work with macOS alone.
    func testEnablesBuiltInModulesOnEveryMac() throws {
        let config = try ConfigManager.parseYAML(bareMac)
        XCTAssertEqual(
            Set(config.moduleConfigs.keys),
            [
                "application", "system", "settings", "audio", "processes", "performance", "window", "tiling",
                "clipboard", "theme", "math", "timer", "emoji", "websearch", "self",
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
        let modulesStart = try XCTUnwrap(bareMac.range(of: "\nmodules:\n"))
        let uncommented = bareMac[..<modulesStart.upperBound]
            + bareMac[modulesStart.upperBound...].replacingOccurrences(of: "\n  # ", with: "\n  ")
        let config = try ConfigManager.parseYAML(String(uncommented))
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
        assertValidDefaults(TilingModule.self)
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
