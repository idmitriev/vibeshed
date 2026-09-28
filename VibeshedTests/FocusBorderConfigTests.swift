@testable import Vibeshed
import XCTest
import Yams

/// The focus border's config lives in the window module's section (it used to be under
/// `tiling`). Covers decoding old and partial configs, validation, and the example config.
@MainActor
final class FocusBorderConfigTests: XCTestCase {
    private let windowSection = """
    horizontalStops:
      - { value: 50, unit: percent }
    verticalStops:
      - { value: 50, unit: percent }
    padding: { top: 0, bottom: 0, left: 0, right: 0, gap: 0 }
    includeMinimized: false
    enlargeShrinkStep: { value: 10, unit: percent }
    """

    func testWindowSectionWithoutFocusBorderStillDecodes() throws {
        let config = try YAMLDecoder().decode(WindowConfig.self, from: windowSection)
        XCTAssertNil(config.focusBorder)
    }

    /// Keys left out keep their defaults, and the retired `color` key is ignored rather
    /// than failing the whole window section.
    func testPartialFocusBorderKeepsDefaults() throws {
        let yaml = windowSection + "\nfocusBorder:\n  width: 2\n  color: \"#ff0000\"\n"
        let border = try XCTUnwrap(YAMLDecoder().decode(WindowConfig.self, from: yaml).focusBorder)
        XCTAssertEqual(border, FocusBorderConfig(width: 2))
        XCTAssertEqual(border.minimumSize, 200)
    }

    /// Configs written before the move still have `focusBorder` under `tiling`; that key
    /// must not break the tiling section.
    func testTilingSectionWithRetiredFocusBorderStillDecodes() throws {
        let yaml = """
        displays: []
        padding: { top: 0, bottom: 0, left: 0, right: 0, gap: 0 }
        autoTile: {}
        focusBorder:
          width: 2
          cornerRadius: 18
        """
        XCTAssertNoThrow(try YAMLDecoder().decode(TilingConfig.self, from: yaml))
    }

    func testValidateRejectsBadFocusBorderValues() {
        var config = WindowConfig.defaultValue
        config.focusBorder = FocusBorderConfig()
        XCTAssertTrue(WindowModule.validate(config).isValid)
        config.focusBorder = FocusBorderConfig(width: 0, cornerRadius: -1, minimumSize: -1, pollingInterval: 0)
        XCTAssertEqual(WindowModule.validate(config).errors.count, 4)
    }

    func testExampleConfigWindowSectionDecodesWithFocusBorder() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.example.yaml")
        let config = try ConfigManager.parseYAML(String(contentsOf: example, encoding: .utf8))
        let window = try YAMLDecoder().decode(WindowConfig.self, from: XCTUnwrap(config.moduleConfigs["window"]))
        XCTAssertTrue(WindowModule.validate(window).isValid)
        let border = try XCTUnwrap(window.focusBorder)
        XCTAssertEqual(border.minimumSize, 200)
    }
}
