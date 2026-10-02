@testable import Vibeshed
import XCTest
import Yams

/// Turning modules on by editing config.yaml's text: the user's comments, order and
/// indentation stay as they were.
@MainActor
final class ConfigEditorTests: XCTestCase {
    private let spotify = DefaultConfig.Entry("spotify", "playback controls")

    /// The first-launch config lists missing apps' modules commented out; that line is
    /// what gets turned on.
    func testUncommentsTheModuleTheFirstLaunchConfigListed() throws {
        let yaml = DefaultConfig.yaml(detected: [])
        let edit = ConfigEditor.enablingModules([spotify], in: yaml)

        XCTAssertEqual(edit.enabled, ["spotify"])
        XCTAssertFalse(edit.yaml.contains("# spotify:"))
        XCTAssertTrue(edit.yaml.contains("\n" + moduleLine("spotify", "playback controls") + "\n"))
        XCTAssertEqual(lineCount(edit.yaml), lineCount(yaml), "replaced the commented line in place")
        let modules = try ConfigManager.parseYAML(edit.yaml).moduleConfigs.keys
        XCTAssertTrue(Set(modules).isSuperset(of: ["spotify", "window", "tiling", "self"]))
    }

    /// Without a commented line, the section goes after the last module that's on and
    /// before whatever follows the modules block.
    func testAddsAfterTheLastEnabledModule() throws {
        let yaml = """
        modules:
          application:
          math:
            decimalPlaces: 2
          # timer:   left off on purpose

        # Layout
        layoutCorrection:
          enabled: false

        """
        let edit = ConfigEditor.enablingModules([spotify], in: yaml)
        XCTAssertEqual(edit.yaml, """
        modules:
          application:
          math:
            decimalPlaces: 2
        \(moduleLine("spotify", "playback controls"))
          # timer:   left off on purpose

        # Layout
        layoutCorrection:
          enabled: false

        """)
        XCTAssertFalse(try ConfigManager.parseYAML(edit.yaml).layoutCorrection.enabled)
    }

    /// A module's own commented-out settings stay under it rather than under the new one.
    func testKeepsCommentsWithTheirModule() throws {
        let yaml = """
        modules:
          theme:
            # apps:
            #   ghostty: "Tokyo Night"
            # ghostty: "nested"

        """
        let edit = ConfigEditor.enablingModules([DefaultConfig.Entry("ghostty", "terminals")], in: yaml)
        XCTAssertEqual(edit.enabled, ["ghostty"], "a deeper commented key isn't a module")
        XCTAssertTrue(edit.yaml.hasSuffix("    # ghostty: \"nested\"\n" + moduleLine("ghostty", "terminals") + "\n"))
    }

    func testKeepsTheConfigsIndentAndWritesSettings() throws {
        let yaml = "modules:\n    math:\n        decimalPlaces: 2\n"
        let homebrew = DefaultConfig.Entry("homebrew", "packages", settings: [#"brewPath: "/usr/local/bin/brew""#])
        let edit = ConfigEditor.enablingModules([homebrew], in: yaml)

        let section = moduleLine("homebrew", "packages", indent: 4) + "\n" + #"        brewPath: "/usr/local/bin/brew""#
        XCTAssertTrue(edit.yaml.hasSuffix(section + "\n"))
        let raw = try XCTUnwrap(ConfigManager.parseYAML(edit.yaml).moduleConfigs["homebrew"])
        XCTAssertEqual(try YAMLDecoder().decode(HomebrewConfig.self, from: raw).brewPath, "/usr/local/bin/brew")
    }

    func testLeavesModulesThatAreOnAlone() {
        let yaml = "modules:\n  spotify:\n    showNowPlaying: false\n"
        let edit = ConfigEditor.enablingModules([spotify, spotify], in: yaml)
        XCTAssertEqual(edit.yaml, yaml)
        XCTAssertEqual(edit.enabled, [])
    }

    func testStartsAModulesSectionWhenThereIsNone() {
        let line = moduleLine("spotify", "playback controls")
        XCTAssertEqual(
            ConfigEditor.enablingModules([spotify], in: "keybindings: []\n").yaml,
            "keybindings: []\n\nmodules:\n\(line)\n"
        )
        XCTAssertEqual(ConfigEditor.enablingModules([spotify], in: "").yaml, "modules:\n\(line)\n")
    }

    func testLeavesWhatItCantEditSafelyAlone() {
        for yaml in ["modules: [\n", "modules: {math: {}}\n", "- not\n- a mapping\n"] {
            let edit = ConfigEditor.enablingModules([spotify], in: yaml)
            XCTAssertEqual(edit.yaml, yaml, yaml)
            XCTAssertEqual(edit.enabled, [], yaml)
        }
    }

    /// The real example config, comments and all: only the new section changes.
    func testExampleConfigKeepsEverythingElse() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.example.yaml")
        let yaml = try String(contentsOf: example, encoding: .utf8)
        let edit = ConfigEditor.enablingModules([DefaultConfig.Entry("newModule", "test")], in: yaml)
        XCTAssertEqual(edit.enabled, ["newModule"])

        let before = try ConfigManager.parseYAML(yaml)
        var after = try ConfigManager.parseYAML(edit.yaml)
        XCTAssertNotNil(after.moduleConfigs.removeValue(forKey: "newModule"))
        XCTAssertEqual(after, before)
        XCTAssertEqual(lineCount(edit.yaml), lineCount(yaml) + 1)
    }

    // MARK: - Helpers

    /// A module's line as the generator writes it, its comment 16 columns past the indent.
    private func moduleLine(_ moduleID: String, _ comment: String, indent: Int = 2) -> String {
        let key = String(repeating: " ", count: indent) + moduleID + ":"
        return key + String(repeating: " ", count: indent + 16 - key.count) + "# " + comment
    }

    private func lineCount(_ text: String) -> Int {
        text.components(separatedBy: "\n").count
    }
}
