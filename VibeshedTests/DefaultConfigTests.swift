@testable import Vibeshed
import XCTest

@MainActor
final class DefaultConfigTests: XCTestCase {
    func testPickerHotkeyParses() throws {
        let config = try ConfigManager.parseYAML(DefaultConfig.yaml)
        XCTAssertEqual(config.keybindings.count, 1)
        let binding = try XCTUnwrap(config.keybindings.first)
        XCTAssertEqual(binding.action, "app/togglePicker")
        XCTAssertNoThrow(try KeyComboParser.parse(binding.combo))
    }

    func testLeavesDefaultBrowserAlone() throws {
        let config = try ConfigManager.parseYAML(DefaultConfig.yaml)
        XCTAssertFalse(config.urlRouting.registerAsDefaultBrowser)
    }

    /// Only modules backed by macOS itself — none that assume a third-party app
    /// is installed or need an extra privacy permission.
    func testEnablesOnlyBuiltInModules() throws {
        let config = try ConfigManager.parseYAML(DefaultConfig.yaml)
        XCTAssertEqual(
            Set(config.moduleConfigs.keys),
            [
                "application", "system", "settings", "audio", "processes",
                "math", "timer", "emoji", "websearch", "self",
            ]
        )
    }

    func testEnabledModulesNeedNoPermissionsAndHaveValidDefaults() {
        assertUsable(ApplicationModule.self)
        assertUsable(SystemModule.self)
        assertUsable(SettingsModule.self)
        assertUsable(AudioModule.self)
        assertUsable(ProcessesModule.self)
        assertUsable(MathModule.self)
        assertUsable(TimerModule.self)
        assertUsable(EmojiModule.self)
        assertUsable(WebSearchModule.self)
        assertUsable(SelfModule.self)
    }

    /// Each section is empty, so the module runs on its `defaultConfig`.
    private func assertUsable<M: ModuleConfigurable>(
        _ module: M.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(M.requiredPermissions.isEmpty, "\(M.self) requires permissions", file: file, line: line)
        guard let defaults = M.defaultConfig else {
            return XCTFail("\(M.self) has no defaultConfig", file: file, line: line)
        }
        XCTAssertTrue(M.validate(defaults).isValid, "\(M.self) defaults invalid", file: file, line: line)
    }
}
