import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Vibeshed
import XCTest

final class ThemeGeneratorTests: XCTestCase {
    private func image(_ fill: (CGContext) -> Void) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        fill(context)
        return try XCTUnwrap(context.makeImage())
    }

    private func fill(_ context: CGContext, _ rect: CGRect, _ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(rect)
    }

    func testDarkBlueWallpaper() throws {
        let wallpaper = try image { context in
            context.setFillColor(CGColor(srgbRed: 0.05, green: 0.07, blue: 0.15, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.5, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        let raw = try XCTUnwrap(ThemeGenerator.palette(from: wallpaper))
        let palette = try ThemePalette.resolve(raw)
        XCTAssertEqual(palette.mode, .dark)
        XCTAssertLessThan(palette.background.relativeLuminance, 0.05)
        XCTAssertGreaterThan(palette.foreground.contrastRatio(with: palette.background), 7)
        let accentHue = palette.accent.hsl.hue
        XCTAssertLessThan(ThemeColor.hueDistance(accentHue, 216), 20, "accent comes from the vivid blue")
        XCTAssertLessThan(ThemeColor.hueDistance(palette.red.hsl.hue, 0), 30, "red stays red")
    }

    func testLightWallpaperYieldsLightTheme() throws {
        let wallpaper = try image { context in
            context.setFillColor(CGColor(srgbRed: 0.95, green: 0.93, blue: 0.88, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        let palette = try ThemePalette.resolve(XCTUnwrap(ThemeGenerator.palette(from: wallpaper)))
        XCTAssertEqual(palette.mode, .light)
        XCTAssertGreaterThan(palette.foreground.contrastRatio(with: palette.background), 7)
    }

    /// Like Apple's dark "hello Orange": deep reds, a vermilion band and a thin bright
    /// orange rim. The accent is the rim, not the more saturated but darker vermilion,
    /// which turns salmon once lightened to accent lightness.
    func testAccentIsTheGlowNotTheRedItFadesInto() throws {
        let wallpaper = try image { context in
            fill(context, CGRect(x: 0, y: 0, width: 64, height: 64), 0.29, 0, 0)
            fill(context, CGRect(x: 32, y: 0, width: 32, height: 64), 0.78, 0.2, 0.1)
            fill(context, CGRect(x: 0, y: 12, width: 64, height: 8), 1, 0.34, 0.13) // vermilion, hue 14.5
            fill(context, CGRect(x: 0, y: 40, width: 64, height: 4), 0.99, 0.53, 0.24) // rim, hue 23.2
        }
        let palette = try ThemePalette.resolve(XCTUnwrap(ThemeGenerator.palette(from: wallpaper)))
        XCTAssertEqual(palette.mode, .dark)
        XCTAssertLessThan(ThemeColor.hueDistance(palette.accent.hsl.hue, 23.2), 2)
        XCTAssertEqual(MacAccentColor.nearest(to: palette.accent), .orange)
    }

    /// Each image color pulls only the ANSI slot it's nearest: a red-orange (hue 18.4) is
    /// within reach of red and yellow too, but only moves orange.
    func testImageColorsTintOnlyTheirNearestSlot() throws {
        let wallpaper = try image { context in
            fill(context, CGRect(x: 0, y: 0, width: 64, height: 64), 0.1, 0.06, 0.04)
            fill(context, CGRect(x: 0, y: 0, width: 64, height: 32), 0.91, 0.39, 0.16)
        }
        let palette = try ThemePalette.resolve(XCTUnwrap(ThemeGenerator.palette(from: wallpaper)))
        XCTAssertLessThan(ThemeColor.hueDistance(palette.orange.hsl.hue, 21.7), 2, "halfway to orange's 25")
        XCTAssertLessThan(ThemeColor.hueDistance(palette.yellow.hsl.hue, 45), 2)
        XCTAssertLessThan(ThemeColor.hueDistance(palette.red.hsl.hue, 355), 2)
    }
}

final class DynamicDesktopTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return try XCTUnwrap(context.makeImage())
    }

    /// A multi-image file described the way macOS's dynamic HEICs are (TIFF, since HEIC
    /// encoding isn't available everywhere).
    private func desktop(_ images: [CGImage], _ name: String? = nil, _ descriptor: [String: Any] = [:]) throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).tiff")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, images.count, nil
        ))
        let metadata = CGImageMetadataCreateMutable()
        if let name {
            let namespace = "http://ns.apple.com/namespace/1.0/" as CFString
            let prefix = "apple_desktop" as CFString
            XCTAssertTrue(CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil))
            let plist = try PropertyListSerialization.data(fromPropertyList: descriptor, format: .binary, options: 0)
            let path = "apple_desktop:\(name)" as CFString
            XCTAssertTrue(CGImageMetadataSetValueWithPath(metadata, nil, path, plist.base64EncodedString() as CFString))
        }
        for (index, image) in images.enumerated() {
            CGImageDestinationAddImageAndMetadata(destination, image, index == 0 ? metadata : nil, nil)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func index(_ url: URL, dark: Bool) throws -> Int? {
        try DynamicDesktop.imageIndex(in: XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil)), dark: dark)
    }

    private func color(of image: CGImage) throws -> ThemeColor {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return ThemeColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255, blue: Double(pixel[2]) / 255)
    }

    func testLightDarkPairFollowsTheAppearance() throws {
        let url = try desktop([solid(1, 0.85, 0.75), solid(0.3, 0.02, 0)], "apr", ["l": 0, "d": 1])
        XCTAssertEqual(try index(url, dark: false), 0)
        XCTAssertEqual(try index(url, dark: true), 1)

        let dark = try XCTUnwrap(DynamicDesktop.thumbnail(of: url, dark: true, maxPixelSize: 8))
        XCTAssertTrue(dark.followsAppearance)
        XCTAssertLessThan(try color(of: dark.image).relativeLuminance, 0.05, "the dark picture, not the first")
    }

    func testSunPositionDesktops() throws {
        let images = try [solid(0.9, 0.9, 1), solid(0.1, 0.1, 0.2), solid(1, 0.7, 0.4)]
        let positions: [[String: Any]] = [
            ["i": 0, "a": 60.0, "z": 180.0], ["i": 1, "a": -40.0, "z": 0.0], ["i": 2, "a": 5.0, "z": 270.0],
        ]
        let paired = try desktop(images, "solar", ["ap": ["l": 2, "d": 1], "si": positions])
        XCTAssertEqual(try index(paired, dark: false), 2, "the light/dark pair wins")
        XCTAssertEqual(try index(paired, dark: true), 1)

        let unpaired = try desktop(images, "solar", ["si": positions])
        XCTAssertEqual(try index(unpaired, dark: false), 0, "highest sun")
        XCTAssertEqual(try index(unpaired, dark: true), 1, "lowest sun")
    }

    func testPlainImagesAreNotDynamic() throws {
        let single = try desktop([solid(0.2, 0.4, 0.8)])
        XCTAssertNil(try index(single, dark: true))
        XCTAssertEqual(DynamicDesktop.thumbnail(of: single, dark: true, maxPixelSize: 8)?.followsAppearance, false)
        XCTAssertNil(try index(desktop([solid(1, 1, 1), solid(0, 0, 0)]), dark: true), "no descriptor")
        XCTAssertNil(try index(desktop([solid(1, 1, 1), solid(0, 0, 0)], "apr", ["l": 0, "d": 5]), dark: true))
    }

    /// The generated theme keeps the appearance the picture was chosen for, even when the
    /// picture's lightness alone would say otherwise; a plain image still decides by lightness.
    func testGeneratedThemeKeepsTheAppearance() throws {
        let pair = try desktop([solid(0.8, 0.45, 0.3), solid(0.25, 0.03, 0.01)], "apr", ["l": 0, "d": 1])
        XCTAssertEqual(ThemeGenerator.palette(fromWallpaper: pair, dark: false)?["mode"], "light")
        XCTAssertEqual(ThemeGenerator.palette(fromWallpaper: pair, dark: true)?["mode"], "dark")

        let plain = try desktop([solid(0.95, 0.93, 0.88)])
        XCTAssertEqual(ThemeGenerator.palette(fromWallpaper: plain, dark: true)?["mode"], "light")
    }
}
