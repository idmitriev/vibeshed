@testable import Vibeshed
import XCTest

@MainActor
final class OverlayConfigTests: XCTestCase {
    private func overlay(_ yaml: String) throws -> AppConfig.OverlayConfig? {
        try ConfigManager.parseYAML(yaml).appearance.overlay
    }

    // MARK: - Presence

    func testAbsentSectionMeansNoOverlay() throws {
        let config = try ConfigManager.parseYAML("appearance:\n  panelWidth: 800\n")
        XCTAssertNil(config.appearance.overlay)
        XCTAssertNil(config.appearance.activeOverlay)
    }

    func testEmptySectionEnablesDefaults() throws {
        let yaml = """
        appearance:
          overlay:
        """
        XCTAssertEqual(try overlay(yaml), AppConfig.OverlayConfig())
    }

    func testBooleanShorthand() throws {
        XCTAssertEqual(try overlay("appearance:\n  overlay: true\n"), AppConfig.OverlayConfig())
        XCTAssertNil(try overlay("appearance:\n  overlay: false\n"))
    }

    /// The commented-out block in config.example.yaml, uncommented, is exactly the defaults.
    func testExampleConfigDocumentsTheDefaults() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.example.yaml")
        let lines = try String(contentsOf: example, encoding: .utf8).components(separatedBy: "\n")
        let start = try XCTUnwrap(lines.firstIndex(of: "  # overlay:"))
        let fields = lines[(start + 1)...].prefix { $0.hasPrefix("  #   ") }
        XCTAssertFalse(fields.isEmpty)
        let yaml = (["appearance:", "  overlay:"] + fields.map { "  " + $0.dropFirst(4) }).joined(separator: "\n")
        XCTAssertEqual(try overlay(yaml), AppConfig.OverlayConfig())
    }

    func testEnabledFalseKeepsSettingsButIsInactive() throws {
        let yaml = """
        appearance:
          overlay:
            enabled: false
            blur: 40
        """
        let appearance = try ConfigManager.parseYAML(yaml).appearance
        XCTAssertEqual(appearance.overlay?.blur, 40)
        XCTAssertNil(appearance.activeOverlay)
    }

    // MARK: - Fields

    func testParsesEveryField() throws {
        let yaml = """
        appearance:
          overlay:
            blur: 12
            saturation: 0.5
            material: hud
            color: "#102030"
            opacity: 0.4
            vignette: 0.6
            grain: 0.2
            allScreens: true
            clickThrough: true
            showAnimation: iris
            showDuration: 0.45
            hideAnimation: blur
            hideDuration: 0.1
        """
        let config = try XCTUnwrap(overlay(yaml))
        XCTAssertEqual(config.blur, 12)
        XCTAssertEqual(config.saturation, 0.5)
        XCTAssertEqual(config.material, .hud)
        XCTAssertEqual(config.color, try .fixed(XCTUnwrap(ThemeColor(hex: "#102030"))))
        XCTAssertEqual(config.opacity, 0.4)
        XCTAssertEqual(config.vignette, 0.6)
        XCTAssertEqual(config.grain, 0.2)
        XCTAssertTrue(config.allScreens)
        XCTAssertTrue(config.clickThrough)
        XCTAssertEqual(config.showAnimation, .iris)
        XCTAssertEqual(config.showDuration, 0.45)
        XCTAssertEqual(config.hideAnimation, .blur)
        XCTAssertEqual(config.hideDuration, 0.1)
    }

    func testMissingFieldsKeepDefaults() throws {
        let config = try XCTUnwrap(overlay("appearance:\n  overlay:\n    blur: 8\n"))
        var expected = AppConfig.OverlayConfig()
        expected.blur = 8
        XCTAssertEqual(config, expected)
    }

    func testNamesMatchCaseInsensitively() throws {
        let yaml = """
        appearance:
          overlay:
            material: FULLSCREEN
            showAnimation: Iris
            color: Accent
        """
        let config = try XCTUnwrap(overlay(yaml))
        XCTAssertEqual(config.material, .fullScreen)
        XCTAssertEqual(config.showAnimation, .iris)
        XCTAssertEqual(config.color, .accent)
    }

    func testOutOfRangeValuesAreClamped() throws {
        let yaml = """
        appearance:
          overlay:
            blur: -4
            saturation: 9
            opacity: 1.5
            vignette: -1
            showDuration: 10
        """
        let config = try XCTUnwrap(overlay(yaml))
        XCTAssertEqual(config.blur, 0)
        XCTAssertEqual(config.saturation, 3)
        XCTAssertEqual(config.opacity, 1)
        XCTAssertEqual(config.vignette, 0)
        XCTAssertEqual(config.showDuration, 2)
    }

    func testBadFieldFallsBackAlone() throws {
        let yaml = """
        appearance:
          panelWidth: 900
          overlay:
            blur: lots
            color: "not a color"
            showAnimation: wobble
            opacity: 0.5
        """
        let appearance = try ConfigManager.parseYAML(yaml).appearance
        let config = try XCTUnwrap(appearance.overlay)
        let defaults = AppConfig.OverlayConfig()
        XCTAssertEqual(config.blur, defaults.blur)
        XCTAssertEqual(config.color, defaults.color)
        XCTAssertEqual(config.showAnimation, defaults.showAnimation)
        // Valid neighbours survive, in the overlay and in the rest of `appearance`.
        XCTAssertEqual(config.opacity, 0.5)
        XCTAssertEqual(appearance.panelWidth, 900)
    }

    func testNonMappingOverlayFallsBackToDefaultsWithoutLosingPanelSettings() throws {
        let appearance = try ConfigManager.parseYAML("appearance:\n  panelWidth: 900\n  overlay: 3\n").appearance
        XCTAssertEqual(appearance.overlay, AppConfig.OverlayConfig())
        XCTAssertEqual(appearance.panelWidth, 900)
    }

    func testColorValues() {
        XCTAssertEqual(OverlayColor("theme"), .theme)
        XCTAssertEqual(OverlayColor(" accent "), .accent)
        XCTAssertEqual(OverlayColor("#fff"), .fixed(.white))
        XCTAssertEqual(OverlayColor("000000"), .fixed(.black))
        XCTAssertNil(OverlayColor("#12345"))
        XCTAssertEqual(OverlayColor.fixed(.white).configValue, "#ffffff")
    }

    // MARK: - Partial appearance

    func testPartialAppearanceKeepsOtherDefaults() throws {
        let appearance = try ConfigManager.parseYAML("appearance:\n  panelWidth: 900\n").appearance
        XCTAssertEqual(appearance.panelWidth, 900)
        XCTAssertEqual(appearance.panelHeight, AppConfig.AppearanceConfig().panelHeight)
        XCTAssertEqual(appearance.rowHeight, AppConfig.AppearanceConfig().rowHeight)
    }

    // MARK: - Resolved style

    func testThemeColorFollowsPaletteThenAppearance() throws {
        let palette = try ThemePalette.resolve(BuiltInThemes.tokyoNight.colors, mode: .dark)
        let accent = ThemeColor(red: 1, green: 0, blue: 0)
        func tint(_ color: OverlayColor, _ palette: ThemePalette?, dark: Bool = true) -> ThemeColor {
            OverlayStyle.tint(for: color, palette: palette, accent: accent, isDarkAppearance: dark)
        }
        XCTAssertEqual(tint(.theme, palette), palette.darkerBackground)
        XCTAssertEqual(tint(.theme, nil), .black)
        XCTAssertEqual(tint(.theme, nil, dark: false), .white)
        XCTAssertEqual(tint(.accent, palette), accent)
        XCTAssertEqual(tint(.fixed(.white), palette), .white)
    }

    func testReduceTransparencyDropsBlurAndMaterial() {
        var config = AppConfig.OverlayConfig()
        config.material = .hud
        let reduced = OverlayStyle(config: config, tint: .black, reduceTransparency: true)
        XCTAssertEqual(reduced.blur, 0)
        XCTAssertEqual(reduced.material, OverlayMaterial.none)
        XCTAssertFalse(reduced.usesBackdrop)
        XCTAssertEqual(reduced.opacity, config.opacity)

        let full = OverlayStyle(config: config, tint: .black, reduceTransparency: false)
        XCTAssertEqual(full.blur, config.blur)
        XCTAssertTrue(full.usesBackdrop)
    }

    // MARK: - Geometry

    func testCoverRadiusReachesTheFarthestCorner() {
        let size = CGSize(width: 1000, height: 600)
        XCTAssertEqual(OverlayGeometry.coverRadius(from: CGPoint(x: 500, y: 300), in: size), hypot(500, 300))
        XCTAssertEqual(OverlayGeometry.coverRadius(from: CGPoint(x: 100, y: 500), in: size), hypot(900, 500))
    }

    func testRadialPointsDescribeACircle() {
        let size = CGSize(width: 1000, height: 500)
        let points = OverlayGeometry.radialPoints(focus: CGPoint(x: 250, y: 250), radius: 100, in: size)
        XCTAssertEqual(points.start, CGPoint(x: 0.25, y: 0.5))
        // Same 100pt radius on both axes, whatever the aspect ratio.
        XCTAssertEqual((points.end.x - points.start.x) * size.width, 100, accuracy: 1e-9)
        XCTAssertEqual((points.end.y - points.start.y) * size.height, 100, accuracy: 1e-9)
    }

    func testCaptureScaleKeepsTheMaterialRatio() {
        XCTAssertEqual(BackdropBlurView.captureScale(forRadius: 30), 0.125)
        XCTAssertEqual(BackdropBlurView.captureScale(forRadius: 60), 0.125)
        XCTAssertEqual(BackdropBlurView.captureScale(forRadius: 7.5), 0.5)
        XCTAssertEqual(BackdropBlurView.captureScale(forRadius: 2), 1)
        XCTAssertEqual(BackdropBlurView.captureScale(forRadius: 0), 1)
    }

    // MARK: - Grain

    func testGrainTileIsStableAndBalanced() throws {
        let first = try XCTUnwrap(OverlayGrain.makeTile(size: 64, seed: 7))
        let second = try XCTUnwrap(OverlayGrain.makeTile(size: 64, seed: 7))
        let firstBytes = try XCTUnwrap(first.dataProvider?.data as Data?)
        XCTAssertEqual(firstBytes, second.dataProvider?.data as Data?)
        XCTAssertEqual(first.width, 64)

        // About as many light specks as dark ones, so the grain doesn't shift brightness.
        var light = 0
        var dark = 0
        for pixel in stride(from: 0, to: firstBytes.count, by: 4) where firstBytes[pixel + 3] > 0 {
            if firstBytes[pixel] > 0 { light += 1 } else { dark += 1 }
        }
        XCTAssertEqual(Double(light) / Double(light + dark), 0.5, accuracy: 0.05)
    }
}
