@testable import Vibeshed
import XCTest

final class GhosttyAppTests: XCTestCase {
    func testVersionParsingAndGates() throws {
        let released = try XCTUnwrap(GhosttyApp.Version(parsing: "1.3.1"))
        XCTAssertEqual(released, GhosttyApp.Version(major: 1, minor: 3))
        XCTAssertEqual(GhosttyApp.Version(parsing: "1.3.2-dev"), GhosttyApp.Version(major: 1, minor: 3))
        XCTAssertEqual(GhosttyApp.Version(parsing: "1.12"), GhosttyApp.Version(major: 1, minor: 12))
        XCTAssertNil(GhosttyApp.Version(parsing: "tip"))
        XCTAssertNil(GhosttyApp.Version(parsing: "1"))

        XCTAssertTrue(released >= GhosttyApp.scriptingVersion)
        XCTAssertTrue(GhosttyApp.Version(major: 1, minor: 2) < GhosttyApp.scriptingVersion)
        XCTAssertTrue(GhosttyApp.Version(major: 1, minor: 2) >= GhosttyApp.reloadSignalVersion)
        XCTAssertTrue(GhosttyApp.Version(major: 1, minor: 1) < GhosttyApp.reloadSignalVersion)
        XCTAssertTrue(GhosttyApp.Version(major: 1, minor: 12) > GhosttyApp.Version(major: 1, minor: 3))
        XCTAssertTrue(GhosttyApp.Version(major: 2, minor: 0) > GhosttyApp.Version(major: 1, minor: 9))
    }

    func testReadsVersionFromBundleInfoPlist() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).app")
        let contents = bundle.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundle) }
        let plist: NSDictionary = ["CFBundleShortVersionString": "1.2.3"]
        try plist.write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertEqual(GhosttyApp.version(ofBundleAt: bundle), GhosttyApp.Version(major: 1, minor: 2))
        XCTAssertNil(GhosttyApp.version(ofBundleAt: bundle.deletingLastPathComponent().appendingPathComponent("x")))
    }
}

final class GhosttyManagerTests: XCTestCase {
    func testParsesTerminalListing() {
        let output = """
        A1B2\t~/Projects/vibeshed\t/Users/me/Projects/vibeshed\t1\t1
        C3D4\tvim README.md\t\t1\t2
        E5F6\t\t/tmp\t2\t1
        truncated line\t1
        \t\t\t1\t1

        """
        let terminals = GhosttyManager.parseTerminals(output)
        XCTAssertEqual(terminals.map(\.id), ["A1B2", "C3D4", "E5F6"])
        XCTAssertEqual(terminals[0].workingDirectory, "/Users/me/Projects/vibeshed")
        XCTAssertNil(terminals[1].workingDirectory)
        XCTAssertEqual(terminals[1].title, "vim README.md")
        XCTAssertEqual(terminals[2].title, "")
        XCTAssertEqual(terminals[2].location, "Window 2, tab 1")
    }

    func testNewSurfaceScripts() {
        let tab = GhosttyManager.newSurfaceScript(inTab: true, input: #"echo "hi" \ there"#)
        XCTAssertTrue(tab.contains(#"set initial input of cfg to "echo \"hi\" \\ there" & linefeed"#))
        XCTAssertTrue(tab.contains("new tab with configuration cfg"))
        XCTAssertTrue(tab.contains("new window with configuration cfg"), "falls back to a window when none is open")
        XCTAssertTrue(tab.hasPrefix(#"tell application id "com.mitchellh.ghostty""#))
        XCTAssertTrue(tab.hasSuffix("activate\nend tell"))

        let window = GhosttyManager.newSurfaceScript(inTab: false, input: nil)
        XCTAssertFalse(window.contains("configuration"))
        XCTAssertFalse(window.contains("new tab"))
        XCTAssertTrue(window.contains("\nnew window\n"))

        XCTAssertTrue(GhosttyManager.focusScript(terminalID: #"a"b"#).contains(#"focus terminal id "a\"b""#))
    }
}

final class GhosttyModuleTests: XCTestCase {
    private func terminal(_ id: String, title: String, directory: String?, tab: Int = 1) -> GhosttyTerminal {
        GhosttyTerminal(id: id, title: title, workingDirectory: directory, windowIndex: 1, tabIndex: tab)
    }

    func testConfigDecodesPartialSections() throws {
        let config = try JSONDecoder().decode(GhosttyConfig.self, from: Data(#"{ "showCWD": false }"#.utf8))
        XCTAssertFalse(config.showCWD)
        XCTAssertEqual(config.maxResults, 20)
        XCTAssertEqual(config.commands, [:])
        XCTAssertNil(config.enabledActions)
        XCTAssertEqual(try JSONDecoder().decode(GhosttyConfig.self, from: Data("{}".utf8)), GhosttyConfig())

        XCTAssertTrue(GhosttyModule.validate(GhosttyConfig()).isValid)
        var invalid = GhosttyConfig()
        invalid.maxResults = 0
        XCTAssertFalse(GhosttyModule.validate(invalid).isValid)
    }

    func testFixedActionsAndCommands() {
        var config = GhosttyConfig()
        config.commands = ["Top": "btop", "Git": "lazygit"]
        let names = GhosttyModule.fixedActions(config: config, appIcon: nil).map(\.id.actionName)
        XCTAssertEqual(
            names,
            [
                "newWindow",
                "newTab",
                "runCommand",
                "reloadConfig",
                "cmd.\(StableID.hash("Git"))",
                "cmd.\(StableID.hash("Top"))",
            ]
        )
    }

    func testEnabledActionsAcceptFamilyPrefixes() {
        var config = GhosttyConfig()
        config.commands = ["Top": "btop"]
        config.enabledActions = ["newTab", "cmd", "terminal"]
        let terminals = [terminal("T1", title: "zsh", directory: nil)]
        let actions = GhosttyModule.fixedActions(config: config, appIcon: nil)
            + GhosttyModule.terminalActions(terminals, config: config, appIcon: nil)
        let enabled = GhosttyModule.enabled(actions, config: config).map(\.id.actionName)
        XCTAssertEqual(enabled, ["newTab", "cmd.\(StableID.hash("Top"))", "terminal.\(StableID.hash("T1"))"])
    }

    func testTerminalActions() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var config = GhosttyConfig()
        config.maxResults = 2
        let terminals = [
            terminal("T1", title: "~/Projects/app", directory: "\(home)/Projects/app"),
            terminal("T2", title: "htop", directory: "/tmp", tab: 2),
            terminal("T3", title: "", directory: nil, tab: 3),
        ]
        let actions = GhosttyModule.terminalActions(terminals, config: config, appIcon: nil)
        XCTAssertEqual(actions.count, 2, "capped at maxResults")
        XCTAssertEqual(actions[0].subtitle, "Window 1, tab 1", "a title that shows the directory isn't repeated")
        XCTAssertEqual(actions[1].subtitle, "/tmp · Window 1, tab 2")
        XCTAssertGreaterThan(actions[0].relevanceScore, actions[1].relevanceScore)
        XCTAssertTrue(actions[1].keywords.contains("tmp"))
        XCTAssertNotNil(actions[0].terminal)

        config.maxResults = 5
        config.showCWD = false
        let all = GhosttyModule.terminalActions(terminals, config: config, appIcon: nil)
        XCTAssertEqual(all[1].subtitle, "Window 1, tab 2")
        XCTAssertEqual(all[2].title, "Terminal")
    }

    func testResolvesFixedActionsWithoutListingTerminals() async {
        let module = GhosttyModule()
        let newTab = await module.action(id: ActionID("ghostty/newTab"))
        XCTAssertEqual(newTab?.title, "New Tab")
        let missing = await module.action(id: ActionID("ghostty/bogus"))
        XCTAssertNil(missing)
        let foreign = await module.action(id: ActionID("iterm/newTab"))
        XCTAssertNil(foreign)
    }
}

final class GhosttyTargetTests: XCTestCase {
    private let palette = (try? ThemePalette.resolve(BuiltInThemes.dracula.colors, mode: .dark))
        ?? ThemePalette(mode: .dark, colors: [:])

    func testThemeFile() {
        let file = GhosttyTarget.themeFile(palette, themeName: "Dracula")
        let lines = file.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[0].hasPrefix("# Generated by Vibeshed from the \"Dracula\" theme"))
        XCTAssertTrue(lines.contains("background = #282a36"))
        XCTAssertTrue(lines.contains("cursor-text = #282a36"))
        XCTAssertTrue(lines.contains("selection-background = \(palette.selectionBackground.hex)"))
        XCTAssertTrue(lines.contains("palette = 15=\(palette.ansi[15].hex)"))
        XCTAssertEqual(lines.filter { $0.hasPrefix("palette = ") }.count, 16)
        XCTAssertTrue(file.hasSuffix("\n"))
    }

    func testReplacesOnlyThemeLines() {
        let config = """
        # theme = Commented
        font-size = 18
        theme = light:GithubLight,dark:GithubDark
        window-theme = auto
          theme=Nord
        """
        XCTAssertEqual(
            GhosttyTarget.replacingTheme("Vibeshed", in: config),
            """
            # theme = Commented
            font-size = 18
            theme = Vibeshed
            window-theme = auto
            theme = Vibeshed
            """
        )
        XCTAssertNil(GhosttyTarget.replacingTheme("Vibeshed", in: "window-theme = auto\n"))

        XCTAssertEqual(GhosttyTarget.appendingTheme("Vibeshed", to: nil), "theme = Vibeshed\n")
        XCTAssertEqual(GhosttyTarget.appendingTheme("Vibeshed", to: "a = 1"), "a = 1\ntheme = Vibeshed\n")
        XCTAssertEqual(GhosttyTarget.appendingTheme("Vibeshed", to: "a = 1\n"), "a = 1\ntheme = Vibeshed\n")
    }

    func testFindsColorsThatOverrideTheTheme() {
        let config = """
        background = #000000
        # foreground = #ffffff
        background-opacity = 0.9
        palette = 1=#ff0000
        window-theme = auto
        """
        XCTAssertEqual(GhosttyTarget.colorOverrides(in: config), ["background", "palette"])
    }

    func testSelectsThemeAcrossConfigFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ["config", "config.ghostty", "support/config"].map { root.appendingPathComponent($0).path }
        let newFile = root.appendingPathComponent("new/config.ghostty").path
        func read(_ path: String) -> String? {
            try? String(contentsOfFile: path, encoding: .utf8)
        }

        // No config at all: a new file.
        try GhosttyTarget.selectTheme("Vibeshed", paths: paths, newFile: newFile)
        XCTAssertEqual(read(newFile), "theme = Vibeshed\n")

        // No theme line anywhere: appended to the file loaded last.
        try "font-size = 18\n".write(toFile: paths[0], atomically: true, encoding: .utf8)
        try "cursor-style = bar".write(toFile: paths[1], atomically: true, encoding: .utf8)
        try GhosttyTarget.selectTheme("Vibeshed", paths: paths, newFile: newFile)
        XCTAssertEqual(read(paths[0]), "font-size = 18\n")
        XCTAssertEqual(read(paths[1]), "cursor-style = bar\ntheme = Vibeshed\n")

        // Existing theme lines are replaced wherever they are; nothing is appended.
        try "theme = Nord\nfont-size = 18\n".write(toFile: paths[0], atomically: true, encoding: .utf8)
        try GhosttyTarget.selectTheme("Dracula", paths: paths, newFile: newFile)
        XCTAssertEqual(read(paths[0]), "theme = Dracula\nfont-size = 18\n")
        XCTAssertEqual(read(paths[1]), "cursor-style = bar\ntheme = Dracula\n")
        XCTAssertNil(read(paths[2]))
    }

    func testThemeTargetIsWiredIn() {
        XCTAssertTrue(ThemeTargetID.defaults.contains(.ghostty))
        XCTAssertTrue(ThemeApplier.targets.contains { $0.id == .ghostty && $0.supportsPreview })

        var config = ThemeConfig()
        config.themes = [ThemeDefinition(name: "Mine", base: "Nord", apps: ["ghostty": "Nord"])]
        XCTAssertTrue(ThemeModule.validate(config).isValid)
    }

    func testRejectsUnknownOverrideThemes() throws {
        XCTAssertFalse(GhosttyTarget.themeExists("No Such Theme \(UUID().uuidString)"))
        XCTAssertFalse(GhosttyTarget.themeExists("../escape"))
        XCTAssertTrue(GhosttyTarget.themeExists("light:A,dark:B"), "pairs are left to Ghostty")

        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertFalse(GhosttyTarget.themeExists(file.path))
        try "background = #000000\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertTrue(GhosttyTarget.themeExists(file.path))
    }
}
