import AppKit
@testable import Vibeshed
import XCTest

final class FontCatalogTests: XCTestCase {
    private func curated(_ name: String) throws -> FontDefinition {
        try XCTUnwrap(FontCatalog.curated.first { $0.name == name })
    }

    func testEditorsGetThePlainFamilyAndTerminalsThePatchedSingleWidthOne() throws {
        let installed: Set = ["Iosevka", "Iosevka Term", "Iosevka Nerd Font", "IosevkaTerm Nerd Font Mono"]
        let font = try XCTUnwrap(try curated("Iosevka").resolve(installed: installed))
        XCTAssertEqual(font.editorFamily, "Iosevka")
        XCTAssertEqual(font.terminalFamily, "IosevkaTerm Nerd Font Mono")
        XCTAssertTrue(font.hasIcons)
        XCTAssertEqual(font.slug, "iosevka")
        XCTAssertEqual(font.families, ["Iosevka", "Iosevka Nerd Font", "Iosevka Term", "IosevkaTerm Nerd Font Mono"])
    }

    func testRecognizesTheFontAnAppIsSetTo() throws {
        struct Stub: FontTarget {
            let id = ThemeTargetID.ghostty
            let displayName = "Stub"
            let family: String?
            func apply(_: FontApplyRequest) async -> ThemeTargetOutcome { .applied() }
            func currentFamily(config _: ThemeConfig) -> String? { family }
        }
        let installed: Set = ["Menlo", "Iosevka", "Iosevka Nerd Font"]
        let fonts = FontCatalog.fonts(config: ThemeConfig(), installed: installed)
        let targets: [any FontTarget] = [Stub(family: nil), Stub(family: "Iosevka Nerd Font"), Stub(family: "Menlo")]
        // Only when no font has been applied with Vibeshed (defaults of the test process).
        if CommittedFont.current == nil {
            XCTAssertEqual(FontCatalog.current(among: fonts, targets: targets, config: ThemeConfig())?.name, "Iosevka")
        }
        let ghostty = "# font-family = A\nfont-family = \"\"\nfont-family = \"B C\"\n"
        XCTAssertEqual(GhosttyFontTarget.family(in: ghostty), "B C")
    }

    func testPatchedOnlyInstallsAreUsedEverywhere() throws {
        let hack = try XCTUnwrap(try curated("Hack").resolve(installed: ["Hack Nerd Font", "Hack Nerd Font Mono"]))
        XCTAssertEqual(hack.editorFamily, "Hack Nerd Font")
        XCTAssertEqual(hack.terminalFamily, "Hack Nerd Font Mono")

        let maple = try XCTUnwrap(try curated("Maple Mono").resolve(installed: ["Maple Mono NF"]))
        XCTAssertEqual(maple.terminalFamily, "Maple Mono NF")
        XCTAssertTrue(maple.hasIcons)
    }

    func testPlainOnlyInstallsHaveNoIcons() throws {
        let font = try XCTUnwrap(try curated("JetBrains Mono").resolve(installed: ["JetBrains Mono"]))
        XCTAssertEqual(font.terminalFamily, "JetBrains Mono")
        XCTAssertFalse(font.hasIcons)
        XCTAssertNil(try curated("JetBrains Mono").resolve(installed: ["JetBrains Mono NL"]))
    }

    func testListsInstalledCuratedAndConfiguredFontsByName() {
        var config = ThemeConfig()
        config.fonts = ["My Mono", "Missing Mono", "menlo"]
        let fonts = FontCatalog.fonts(config: config, installed: ["Menlo", "menlo", "My Mono", "SF Mono", "Fira Code"])
        XCTAssertEqual(fonts.map(\.name), ["Fira Code", "menlo", "My Mono", "SF Mono"])
        // A configured font replaces the curated one with the same name.
        XCTAssertEqual(fonts.first { $0.slug == "menlo" }?.summary, "From config")
    }

    func testCuratedNamesAndSlugsAreUnique() {
        let slugs = FontCatalog.curated.map { ResolvedTheme.slug(for: $0.name) }
        XCTAssertEqual(Set(slugs).count, slugs.count)
        XCTAssertFalse(slugs.contains(where: \.isEmpty))
    }

    func testFacesKeepTheReferenceWeight() {
        XCTAssertEqual(FontFaces.face(of: "Menlo", like: nil), "Menlo-Regular")
        XCTAssertEqual(FontFaces.face(of: "Menlo", like: "Monaco"), "Menlo-Regular")
        XCTAssertEqual(FontFaces.face(of: "Menlo", like: "Courier-Bold"), "Menlo-Bold")
        XCTAssertNil(FontFaces.face(of: "No Such Family", like: nil))
    }
}

final class FontTargetTests: XCTestCase {
    private let font = ResolvedFont(
        name: "JetBrains Mono", slug: "jetbrains-mono", editorFamily: "JetBrains Mono",
        terminalFamily: "JetBrainsMono Nerd Font Mono", families: ["JetBrains Mono", "JetBrainsMono Nerd Font Mono"],
        summary: "JetBrains · ligatures"
    )

    func testGhosttyReplacesTheFirstFamilyAndKeepsFallbacks() {
        let config = """
        # font-family = Commented
        font-family = ""
        font-family = Iosevka Nerd Font
        font-family = Symbols Nerd Font
        font-size = 18
        """
        XCTAssertEqual(GhosttyFontTarget.replacingFamily("Hack", in: config), """
        # font-family = Commented
        font-family = ""
        font-family = Hack
        font-family = Symbols Nerd Font
        font-size = 18
        """)
        XCTAssertNil(GhosttyFontTarget.replacingFamily("Hack", in: "theme = Vibeshed\nfont-size = 12\n"))
    }

    func testGhosttyAppendsToTheLastConfigWhenNoneNamesAFont() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("config").path
        let last = directory.appendingPathComponent("config.ghostty").path
        try "theme = Vibeshed".write(toFile: first, atomically: true, encoding: .utf8)
        try "font-size = 14\n".write(toFile: last, atomically: true, encoding: .utf8)

        try GhosttyFontTarget.selectFamily("Hack", paths: [first, last], newFile: last)
        XCTAssertEqual(ThemeFiles.read(first), "theme = Vibeshed")
        XCTAssertEqual(ThemeFiles.read(last), "font-size = 14\nfont-family = Hack\n")

        try GhosttyFontTarget.selectFamily("Menlo", paths: [first, last], newFile: last)
        XCTAssertEqual(ThemeFiles.read(last), "font-size = 14\nfont-family = Menlo\n")
    }

    func testVSCodeFontListsKeepFallbacks() {
        XCTAssertEqual(VSCodeFontTarget.fontList("JetBrains Mono", replacingFirstOf: "Iosevka"), "'JetBrains Mono'")
        XCTAssertEqual(VSCodeFontTarget.fontList("Hack", replacingFirstOf: nil), "Hack")
        XCTAssertEqual(
            VSCodeFontTarget.fontList(
                "JetBrains Mono", replacingFirstOf: "'Fira Code', 'JetBrains Mono', Menlo, monospace"
            ),
            "'JetBrains Mono', Menlo, monospace"
        )
        XCTAssertEqual(VSCodeFontTarget.cssName("0xProto"), "'0xProto'")
        XCTAssertEqual(VSCodeFontTarget.cssName("Menlo"), "Menlo")
    }

    func testVSCodeSetsTheTerminalFontOnlyWhereItHasItsOwn() throws {
        var settings = JSONCDocument(text: """
        {
          // editor
          "editor.fontFamily": "Iosevka, monospace",
          "editor.fontSize": 15,
        }
        """)
        try VSCodeFontTarget.apply(font, to: &settings)
        XCTAssertEqual(settings.text, """
        {
          // editor
          "editor.fontFamily": "'JetBrains Mono', monospace",
          "editor.fontSize": 15,
        }
        """)

        var withTerminal = JSONCDocument(text: "{\n  \"terminal.integrated.fontFamily\": \"MesloLGS NF\"\n}\n")
        try VSCodeFontTarget.apply(font, to: &withTerminal)
        XCTAssertEqual(withTerminal.value(forKey: "terminal.integrated.fontFamily") as? String,
                       "'JetBrainsMono Nerd Font Mono'")
        XCTAssertEqual(withTerminal.value(forKey: "editor.fontFamily") as? String, "'JetBrains Mono'")
    }

    func testZedMovesTheUIFontOnlyWhenItFollowedTheBuffer() throws {
        let text = """
        {
          "ui_font_family": "Iosevka Nerd Font",
          "buffer_font_family": "Iosevka Nerd Font",
          "terminal": {
            // keep me
            "font_family": "Iosevka Nerd Font",
            "font_size": 14
          }
        }
        """
        var settings = JSONCDocument(text: text)
        try ZedFontTarget.apply(font, to: &settings)
        XCTAssertEqual(settings.text, """
        {
          "ui_font_family": "JetBrains Mono",
          "buffer_font_family": "JetBrains Mono",
          "terminal": {
            // keep me
            "font_family": "JetBrainsMono Nerd Font Mono",
            "font_size": 14
          }
        }
        """)

        var separateUI = JSONCDocument(text: "{\n  \"ui_font_family\": \".SystemUIFont\",\n  \"terminal\": {}\n}\n")
        try ZedFontTarget.apply(font, to: &separateUI)
        XCTAssertEqual(separateUI.value(forKey: "ui_font_family") as? String, ".SystemUIFont")
        XCTAssertEqual(separateUI.value(forKey: "buffer_font_family") as? String, "JetBrains Mono")
        XCTAssertNil(separateUI.value(at: ["terminal", "font_family"]))
    }

    func testJSONCKeyPaths() throws {
        var document = JSONCDocument(text: "{\n  \"a\": { \"b\": { \"c\": 1 } },\n  \"d\": 2\n}\n")
        XCTAssertEqual(document.value(at: ["a", "b", "c"]) as? Int, 1)
        try document.setValue("x", at: ["a", "b", "c"])
        XCTAssertEqual(document.text, "{\n  \"a\": { \"b\": { \"c\": \"x\" } },\n  \"d\": 2\n}\n")
        XCTAssertThrowsError(try document.setValue(1, at: ["missing", "key"]))
    }

    func testJetBrainsOptions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let editor = directory.appendingPathComponent("editor-font.xml").path
        try """
        <application>
          <component name="DefaultFont">
            <option name="VERSION" value="1" />
            <option name="FONT_SIZE" value="16" />
            <option name="FONT_FAMILY" value="Iosevka Nerd Font" />
          </component>
        </application>
        """.write(toFile: editor, atomically: true, encoding: .utf8)
        try JetBrainsXML.setOption(
            "FONT_FAMILY", "JetBrains Mono", component: "DefaultFont", at: editor, onlyIfSet: false
        )
        let text = try XCTUnwrap(ThemeFiles.read(editor))
        XCTAssertTrue(text.contains(#"<option name="FONT_FAMILY" value="JetBrains Mono""#), text)
        XCTAssertTrue(text.contains(#"<option name="FONT_SIZE" value="16""#), text)

        let fresh = directory.appendingPathComponent("fresh.xml").path
        try JetBrainsXML.setOption("FONT_FAMILY", "Hack", component: "DefaultFont", at: fresh, onlyIfSet: false)
        let created = try XCTUnwrap(ThemeFiles.read(fresh))
        XCTAssertTrue(created.contains(#"<option name="VERSION" value="1""#), created)
        XCTAssertTrue(created.contains(#"<option name="FONT_FAMILY" value="Hack""#), created)

        // The console font follows the editor's unless it's set: left alone.
        let console = directory.appendingPathComponent("console-font.xml").path
        let consoleText = """
        <application>
          <component name="ConsoleFont">
            <option name="VERSION" value="1" />
          </component>
        </application>
        """
        try consoleText.write(toFile: console, atomically: true, encoding: .utf8)
        try JetBrainsXML.setOption("FONT_FAMILY", "Hack", component: "ConsoleFont", at: console, onlyIfSet: true)
        XCTAssertEqual(ThemeFiles.read(console), consoleText)
        let missing = directory.appendingPathComponent("terminal-font.xml").path
        try JetBrainsXML.setOption(
            "FONT_FAMILY", "Hack", component: "TerminalFontOptions", at: missing, onlyIfSet: true
        )
        XCTAssertFalse(ThemeFiles.exists(missing))
    }

    func testJetBrainsSchemeFontOptions() {
        let scheme = """
        <scheme name="_@user_GitHub Light" version="142" parent_scheme="Default">
          <option name="EDITOR_FONT_NAME" value="IosevkaTerm Nerd Font Mono" />
          <option name="CONSOLE_FONT_NAME" value="Iosevka Term" />
        </scheme>
        """
        let updated = JetBrainsFontTarget.replacingOption("EDITOR_FONT_NAME", with: "A&B", in: scheme)
        XCTAssertEqual(updated, scheme.replacingOccurrences(
            of: "value=\"IosevkaTerm Nerd Font Mono\"", with: "value=\"A&amp;B\""
        ))
        XCTAssertNil(JetBrainsFontTarget.replacingOption("EDITOR_FONT_SIZE", with: "1", in: scheme))
    }

    func testITermFontKeepsTheProfilesWeightAndSize() {
        XCTAssertEqual(ITermFontTarget.normalFont("Menlo", like: "Monaco 13"), "Menlo-Regular 13")
        XCTAssertEqual(ITermFontTarget.normalFont("Menlo", like: "Courier-Bold 15.5"), "Menlo-Bold 15.5")
        XCTAssertEqual(ITermFontTarget.normalFont("Menlo", like: nil), "Menlo-Regular 12")
        XCTAssertNil(ITermFontTarget.normalFont("No Such Family", like: nil))
    }

    func testThemeProfilesCarryTheFont() throws {
        let palette = try ThemePalette.resolve(BuiltInThemes.dracula.colors, mode: .dark)
        let iterm = ITermTarget.profile(palette, parent: "Default", normalFont: "Menlo-Regular 13")
        XCTAssertEqual(iterm["Normal Font"] as? String, "Menlo-Regular 13")
        XCTAssertNil(ITermTarget.profile(palette, parent: "Default")["Normal Font"])
        XCTAssertEqual(ITermTarget.baseProfile(parent: nil).keys.sorted(), ["Guid", "Name"])

        let font = try XCTUnwrap(TerminalFontTarget.font("Menlo", like: NSFont(name: "Courier-Bold", size: 14)))
        XCTAssertEqual(font.fontName, "Menlo-Bold")
        XCTAssertEqual(font.pointSize, 14)
        let terminal = TerminalTarget.profile(palette, parent: ["Font": Data([1])], font: font)
        let data = try XCTUnwrap(terminal["Font"] as? Data)
        let decoded = try XCTUnwrap(try NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: data))
        XCTAssertEqual(decoded.fontName, "Menlo-Bold")
        XCTAssertEqual(TerminalTarget.profile(palette, parent: ["Font": Data([1])])["Font"] as? Data, Data([1]))
    }
}

final class ThemeModuleFontTests: XCTestCase {
    private static let scoring = ScoringContext(usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil)

    func testFontActionsListInstalledFonts() async {
        let module = ThemeModule()
        await module.configDidUpdate(ThemeConfig())
        let ids = await module.provideActions(query: "", scoring: Self.scoring).map(\.id.actionName)
        // Menlo ships with macOS.
        XCTAssertTrue(ids.contains("switchFont"))
        XCTAssertTrue(ids.contains("font.menlo"))

        let options = await module.provideParameterOptions(for: "font", in: ThemeModule.switchFontActionID, query: "")
        XCTAssertTrue(options.contains { $0.id == "menlo" })
    }

    func testFontActionsNeedAFontTarget() async {
        var config = ThemeConfig()
        config.targets = ["wallpaper"]
        let module = ThemeModule()
        await module.configDidUpdate(config)
        let ids = await module.provideActions(query: "", scoring: Self.scoring).map(\.id.actionName)
        XCTAssertFalse(ids.contains { $0 == "switchFont" || $0.hasPrefix("font.") })
    }

    func testValidationRejectsEmptyFontNames() {
        var config = ThemeConfig()
        config.fonts = [" "]
        XCTAssertTrue(ThemeModule.validate(config).errors.contains("Font names cannot be empty"))
    }
}
