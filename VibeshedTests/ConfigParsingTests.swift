@testable import Vibeshed
import XCTest

@MainActor
final class ConfigParsingTests: XCTestCase {
    func testEmptyStringYieldsDefaults() throws {
        let config = try ConfigManager.parseYAML("")
        XCTAssertEqual(config, AppConfig())
    }

    func testParsesKeybindings() throws {
        let yaml = """
        keybindings:
          - combo: cmd+space
            action: picker/toggle
          - combo: cmd+shift+r
            remap: escape
        """
        let config = try ConfigManager.parseYAML(yaml)
        XCTAssertEqual(config.keybindings.count, 2)
        XCTAssertEqual(config.keybindings.first?.combo, "cmd+space")
        XCTAssertEqual(config.keybindings.first?.action, "picker/toggle")
        XCTAssertEqual(config.keybindings.last?.remap, "escape")
    }

    func testParsesKeybindingExclusions() throws {
        let yaml = """
        keybindings:
          - combo: cmd+space
            action: picker/toggle
        keybindingExclusions:
          - com.realvnc.vncviewer
          - com.microsoft.rdc.macos
        """
        let config = try ConfigManager.parseYAML(yaml)
        XCTAssertEqual(config.keybindingExclusions, ["com.realvnc.vncviewer", "com.microsoft.rdc.macos"])
        // Exclusions don't disturb the bindings themselves.
        XCTAssertEqual(config.keybindings.count, 1)
    }

    func testMissingKeybindingExclusionsDefaultsToEmpty() throws {
        let yaml = """
        keybindings:
          - combo: cmd+space
            action: picker/toggle
        """
        let config = try ConfigManager.parseYAML(yaml)
        XCTAssertTrue(config.keybindingExclusions.isEmpty)
    }

    func testParsesAppearance() throws {
        // NOTE: AppearanceConfig is Codable with defaulted properties, but Codable
        // synthesis ignores Swift defaults, so YAMLDecoder requires every key.
        let yaml = """
        appearance:
          panelWidth: 900
          panelHeight: 500
          cornerRadius: 20
          rowHeight: 52
          searchBarHeight: 56
        """
        let config = try ConfigManager.parseYAML(yaml)
        XCTAssertEqual(config.appearance.panelWidth, 900)
        XCTAssertEqual(config.appearance.cornerRadius, 20)
    }

    func testStoresEachModuleSectionAsRawData() throws {
        let yaml = """
        modules:
          window:
            gap: 8
          clipboard:
            maxItems: 50
        """
        let config = try ConfigManager.parseYAML(yaml)
        XCTAssertEqual(Set(config.moduleConfigs.keys), ["window", "clipboard"])
        XCTAssertNotNil(config.moduleConfigs["window"])
        // The stored bytes should be the serialized YAML for that section.
        let windowYAML = try String(data: XCTUnwrap(config.moduleConfigs["window"]), encoding: .utf8) ?? ""
        XCTAssertTrue(windowYAML.contains("gap"))
    }

    func testBadSectionFallsBackWithoutDiscardingOthers() throws {
        let yaml = """
        keybindings:
          - combo: cmd+space
            action: picker/toggle
        appearance:
          panelWidth: "not a number"
        """
        let config = try ConfigManager.parseYAML(yaml)
        // The malformed appearance section falls back to defaults…
        XCTAssertEqual(config.appearance, AppConfig().appearance)
        // …without discarding the valid sections around it.
        XCTAssertEqual(config.keybindings.count, 1)
        XCTAssertEqual(config.keybindings.first?.combo, "cmd+space")
    }

    func testIgnoresUnknownTopLevelSections() throws {
        let yaml = """
        somethingUnknown:
          foo: bar
        """
        let config = try ConfigManager.parseYAML(yaml)
        XCTAssertTrue(config.moduleConfigs.isEmpty)
        XCTAssertTrue(config.keybindings.isEmpty)
        // Untouched sections keep their defaults.
        XCTAssertEqual(config.appearance.panelWidth, AppConfig().appearance.panelWidth)
    }
}
