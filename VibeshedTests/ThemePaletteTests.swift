import AppKit
@testable import Vibeshed
import XCTest

final class ThemeColorTests: XCTestCase {
    func testParsesHexForms() throws {
        XCTAssertEqual(ThemeColor(hex: "#7aa2f7")?.hex, "#7aa2f7")
        XCTAssertEqual(ThemeColor(hex: "7AA2F7")?.hex, "#7aa2f7")
        XCTAssertEqual(ThemeColor(hex: "#fff")?.hex, "#ffffff")
        XCTAssertEqual(ThemeColor(hex: "#7aa2f7cc")?.hex, "#7aa2f7", "alpha is dropped")
        XCTAssertNil(ThemeColor(hex: "#12345"))
        XCTAssertNil(ThemeColor(hex: "blue"))
    }

    func testFormats() throws {
        let color = try XCTUnwrap(ThemeColor(hex: "#1a1b26"))
        XCTAssertEqual(color.hexStripped, "1a1b26")
        XCTAssertEqual(color.rgbString, "26,27,38")
        XCTAssertEqual(ThemeColor.white.appleScriptList, "{65535, 65535, 65535}")
    }

    func testMixMatchesOmarchy() throws {
        // omarchy-theme-color: mix #1a1b26 toward black by 25% → #14141d
        let background = try XCTUnwrap(ThemeColor(hex: "#1a1b26"))
        XCTAssertEqual(background.mix(.black, 0.25).hex, "#14141d")
        XCTAssertEqual(background.mix(.white, 0).hex, "#1a1b26")
        XCTAssertEqual(background.mix(.white, 1).hex, "#ffffff")
    }

    func testHSLRoundTrip() throws {
        for hex in ["#f7768e", "#9ece6a", "#7aa2f7", "#bb9af7", "#808080"] {
            let color = try XCTUnwrap(ThemeColor(hex: hex))
            let hsl = color.hsl
            XCTAssertEqual(ThemeColor(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness).hex, hex)
        }
    }

    func testContrastAndLightness() throws {
        XCTAssertEqual(ThemeColor.white.contrastRatio(with: .black), 21, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(ThemeColor(hex: "#fdf6e3")).contrastingText, .black)
        XCTAssertEqual(try XCTUnwrap(ThemeColor(hex: "#1e1e2e")).contrastingText, .white)
        XCTAssertTrue(try XCTUnwrap(ThemeColor(hex: "#eff1f5")).isLight)
        XCTAssertFalse(try XCTUnwrap(ThemeColor(hex: "#282828")).isLight)
    }

    func testHueDistanceWraps() {
        XCTAssertEqual(ThemeColor.hueDistance(350, 10), 20)
        XCTAssertEqual(ThemeColor.hueDistance(10, 350), 20)
        XCTAssertEqual(ThemeColor.hueDistance(0, 180), 180)
    }
}

final class ThemePaletteResolutionTests: XCTestCase {
    private let minimal = [
        "background": "#1a1b26", "foreground": "#c0caf5",
        "red": "#f7768e", "green": "#9ece6a", "yellow": "#e0af68",
        "blue": "#7aa2f7", "magenta": "#bb9af7", "cyan": "#7dcfff",
    ]

    func testMinimalPaletteDerivesEverything() throws {
        let palette = try ThemePalette.resolve(minimal)
        XCTAssertEqual(palette.mode, .dark)
        XCTAssertEqual(palette.accent.hex, "#7aa2f7", "accent falls back to blue")
        XCTAssertEqual(palette.cursor, palette.brightForeground)
        XCTAssertEqual(palette.orange.hex, "#e0af68", "orange falls back to yellow")
        XCTAssertEqual(palette["bright_red"]?.hex, ThemeColor(hex: "#f7768e")?.mix(.white, 0.2).hex)
        XCTAssertEqual(palette.darkBackground.hex, "#14141d")
        XCTAssertEqual(palette.ansi.count, 16)
        XCTAssertEqual(palette["color0"], palette.background)
        XCTAssertEqual(palette["color1"], palette.red)
        XCTAssertEqual(palette["color15"], palette.brightForeground)
        XCTAssertEqual(palette["purple"], palette.magenta)
        XCTAssertEqual(palette["bg"], palette.background, "legacy short names are aliased")
    }

    func testANSIOnlyPalette() throws {
        var raw: [String: String] = [:]
        let hexes = ["#000000", "#cc0000", "#00cc00", "#cccc00", "#0000cc", "#cc00cc", "#00cccc", "#cccccc",
                     "#555555", "#ff5555", "#55ff55", "#ffff55", "#5555ff", "#ff55ff", "#55ffff", "#ffffff"]
        for (index, hex) in hexes.enumerated() {
            raw["color\(index)"] = hex
        }
        let palette = try ThemePalette.resolve(raw)
        XCTAssertEqual(palette.background.hex, "#000000")
        XCTAssertEqual(palette.foreground.hex, "#cccccc")
        XCTAssertEqual(palette.red.hex, "#cc0000")
        XCTAssertEqual(palette["bright_blue"]?.hex, "#5555ff")
        XCTAssertEqual(palette.muted.hex, "#555555")
        XCTAssertEqual(palette.ansi.map(\.hex), hexes)
    }

    func testExplicitANSIColorIsKept() throws {
        var raw = minimal
        raw["color0"] = "#15161e"
        let palette = try ThemePalette.resolve(raw)
        XCTAssertEqual(palette["color0"]?.hex, "#15161e")
        XCTAssertEqual(palette.background.hex, "#1a1b26")
    }

    func testModeDetectionAndOverride() throws {
        var light = minimal
        light["background"] = "#eff1f5"
        XCTAssertEqual(try ThemePalette.resolve(light).mode, .light)
        light["mode"] = "dark"
        XCTAssertEqual(try ThemePalette.resolve(light).mode, .dark)
        XCTAssertEqual(try ThemePalette.resolve(light, mode: .light).mode, .light)
    }

    func testErrors() {
        var invalid = minimal
        invalid["accent"] = "not-a-color"
        XCTAssertThrowsError(try ThemePalette.resolve(invalid)) { error in
            XCTAssertEqual(error as? ThemePaletteError, .invalidColor(key: "accent", value: "not-a-color"))
        }

        var missing = minimal
        missing["cyan"] = nil
        XCTAssertThrowsError(try ThemePalette.resolve(missing)) { error in
            XCTAssertEqual(error as? ThemePaletteError, .missingKeys(["cyan"]))
        }

        var badMode = minimal
        badMode["mode"] = "dim"
        XCTAssertThrowsError(try ThemePalette.resolve(badMode))
    }

    func testEveryBuiltInThemeResolves() throws {
        for definition in BuiltInThemes.all {
            let palette = try ThemePalette.resolve(definition.colors, mode: definition.mode)
            XCTAssertEqual(palette.ansi.count, 16, definition.name)
            XCTAssertEqual(palette.mode, definition.mode, definition.name)
            // Text must stay readable on the theme's own background (Solarized is famously ~4:1).
            XCTAssertGreaterThan(
                palette.foreground.contrastRatio(with: palette.background), 3.5, "\(definition.name) foreground"
            )
        }
    }

    func testBuiltInCatalogIsWellFormed() throws {
        let names = BuiltInThemes.all.map(\.name)
        XCTAssertGreaterThanOrEqual(names.count, 60)
        XCTAssertEqual(Set(names.map(ResolvedTheme.slug)).count, names.count, "slugs must be unique")
        XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        for definition in BuiltInThemes.all {
            let icon = try XCTUnwrap(definition.icon, definition.name)
            let symbol = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            XCTAssertNotNil(symbol, "\(definition.name): no SF Symbol '\(icon)'")
            let palette = try ThemePalette.resolve(definition.colors, mode: definition.mode)
            XCTAssertEqual(palette.mode == .light, palette.background.isLight, "\(definition.name) mode")
            XCTAssertGreaterThan(
                palette.foreground.contrastRatio(with: palette.background), 3.5, "\(definition.name) foreground"
            )
            if palette.mode == .light {
                XCTAssertTrue(palette.darkBackground.isLight, "\(definition.name) sidebar stays light")
            }
        }
    }

    func testCodableRoundTrip() throws {
        let palette = try ThemePalette.resolve(minimal)
        let info = ActiveThemeInfo(name: "Test", slug: "test", palette: palette)
        let decoded = try JSONDecoder().decode(ActiveThemeInfo.self, from: JSONEncoder().encode(info))
        XCTAssertEqual(decoded, info)
    }
}

final class ThemeTemplateRendererTests: XCTestCase {
    private func palette() throws -> ThemePalette {
        try ThemePalette.resolve(BuiltInThemes.tokyoNight.colors, mode: .dark)
    }

    func testOmarchyPlaceholders() throws {
        let template = """
        background = {{ background }}
        palette = 1={{red}}
        strip={{ accent_strip }} rgb={{ accent_rgb }}
        type={{ theme_type }} name={{ theme_name }}
        """
        let output = ThemeTemplateRenderer.render(template, palette: try palette(), themeName: "Tokyo Night")
        XCTAssertEqual(output.text, """
        background = #1a1b26
        palette = 1=#f7768e
        strip=7aa2f7 rgb=122,162,247
        type=dark name=Tokyo Night
        """)
        XCTAssertTrue(output.unresolved.isEmpty)
    }

    func testMixAndDotModifiers() throws {
        let palette = try palette()
        let expected = palette.background.mix(palette.green, 0.15)
        let output = ThemeTemplateRenderer.render(
            "{{ mix background green 15% }} {{ mix_strip background green 0.15 }} {{ accent.rgb }} {{ accent.hex }}",
            palette: palette, themeName: "x"
        )
        XCTAssertEqual(output.text, "\(expected.hex) \(expected.hexStripped) 122,162,247 #7aa2f7")
    }

    func testUnknownPlaceholdersAreKeptAndReported() throws {
        let output = ThemeTemplateRenderer.render(
            "a {{ nope }} b {{ nope }} {{ mix accent nope 10% }} {{ unclosed",
            palette: try palette(), themeName: "x"
        )
        XCTAssertEqual(output.text, "a {{ nope }} b {{ nope }} {{ mix accent nope 10% }} {{ unclosed")
        XCTAssertEqual(output.unresolved, ["nope", "mix accent nope 10%"])
    }
}

final class MacAccentColorTests: XCTestCase {
    func testNearestPreset() throws {
        XCTAssertEqual(MacAccentColor.nearest(to: try XCTUnwrap(ThemeColor(hex: "#7aa2f7"))), .blue)
        XCTAssertEqual(MacAccentColor.nearest(to: try XCTUnwrap(ThemeColor(hex: "#bd93f9"))), .purple)
        XCTAssertEqual(MacAccentColor.nearest(to: try XCTUnwrap(ThemeColor(hex: "#fe8019"))), .orange)
        XCTAssertEqual(MacAccentColor.nearest(to: try XCTUnwrap(ThemeColor(hex: "#a7c080"))), .green)
        XCTAssertEqual(MacAccentColor.nearest(to: try XCTUnwrap(ThemeColor(hex: "#ebbcba"))), .red)
        XCTAssertEqual(MacAccentColor.nearest(to: try XCTUnwrap(ThemeColor(hex: "#8a8a8a"))), .graphite)
    }

    func testNamedLookup() {
        XCTAssertEqual(MacAccentColor.named("Purple"), .purple)
        XCTAssertEqual(MacAccentColor.named("multicolor")?.preferenceValue, nil)
        XCTAssertEqual(MacAccentColor.named("graphite")?.preferenceValue, -1)
        XCTAssertNil(MacAccentColor.named("teal"))
    }
}
