import AppKit
@testable import Vibeshed
import XCTest

final class TerminalThemeTargetTests: XCTestCase {
    private let palette = (try? ThemePalette.resolve(BuiltInThemes.dracula.colors, mode: .dark))
        ?? ThemePalette(mode: .dark, colors: [:])

    func testTerminalProfileCopiesParentWithPaletteColors() throws {
        let parent: [String: Any] = [
            "name": "Pro", "Font": Data([1, 2, 3]), "columnCount": 220, "ProfileCurrentVersion": 2.09,
            "BackgroundColor": Data(), "DynamicANSIForegroundColors": true,
        ]
        let profile = TerminalTarget.profile(palette, parent: parent)
        XCTAssertEqual(profile["name"] as? String, TerminalTarget.profileName)
        XCTAssertEqual(profile["type"] as? String, "Window Settings")
        XCTAssertEqual(profile["Font"] as? Data, Data([1, 2, 3]))
        XCTAssertEqual(profile["columnCount"] as? Int, 220)
        XCTAssertEqual(profile["DynamicANSIForegroundColors"] as? Bool, false)

        func color(_ key: String) throws -> NSColor? {
            try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: XCTUnwrap(profile[key] as? Data))?
                .usingColorSpace(.sRGB)
        }
        let background = try XCTUnwrap(color("BackgroundColor"))
        XCTAssertEqual(background.redComponent, palette.background.red, accuracy: 0.001)
        XCTAssertEqual(background.blueComponent, palette.background.blue, accuracy: 0.001)
        XCTAssertEqual(try color("ANSIBrightWhiteColor")?.greenComponent ?? -1, palette.ansi[15].green, accuracy: 0.001)
        XCTAssertEqual(TerminalTarget.profileColors(palette).count, 21)
        XCTAssertNotNil(TerminalTarget.profile(palette, parent: nil)["ProfileCurrentVersion"])
    }
}
