import CoreGraphics
import Foundation

/// Classic Mac OS (System 7 to Mac OS 9) desktops. All three are bitmaps in the manner of
/// the originals: computed in "Mac pixels" and scaled up by a whole number of device pixels
/// without smoothing, so the edges stay hard at any resolution. Themes pin the desktop
/// color with a `desktop` key.
extension WallpaperCanvas {
    /// A pixel's color, as bytes.
    struct Tone {
        let red: UInt8
        let green: UInt8
        let blue: UInt8

        init(_ color: ThemeColor) {
            red = UInt8(color.red8)
            green = UInt8(color.green8)
            blue = UInt8(color.blue8)
        }

        init(red: Int, green: Int, blue: Int) {
            self.red = UInt8(min(max(red, 0), 255))
            self.green = UInt8(min(max(green, 0), 255))
            self.blue = UInt8(min(max(blue, 0), 255))
        }
    }

    /// Device pixels per Mac pixel: a whole number (1 on a 1080p screen, 2 on a retina laptop
    /// or 4K, 4 on 8K), so a dot is one point across, the size it had on a 72 dpi screen.
    var macPixel: CGFloat { max(1, (height / 1080).rounded()) }

    /// The theme's desktop color, or its accent softened toward the page.
    var classicDesktop: ThemeColor {
        palette["desktop"] ?? (isDark ? palette.accent.mix(base, 0.6) : palette.accent.mix(palette.background, 0.45))
    }

    /// Paints the whole canvas as Mac pixels, anchored at the top-left. `level` picks each
    /// pixel's entry in `tones` from its column and row.
    private func paintMacPixels(_ tones: [Tone], level: (Int, Int) -> Int) {
        paintPixels(dot: macPixel) { column, row in tones[level(column, row)] }
    }

    /// Paints the whole canvas as `dot`-sized pixels (a whole number of device pixels),
    /// anchored at the top-left and scaled up without smoothing. `tone` colors each pixel
    /// from its column and row.
    func paintPixels(dot: CGFloat, tone: (Int, Int) -> Tone) {
        let columns = Int((width / dot).rounded(.up)), rows = Int((height / dot).rounded(.up))
        var pixels = [UInt8](repeating: 255, count: columns * rows * 4)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let color = tone(column, row)
                let offset = (row * columns + column) * 4
                pixels[offset] = color.red
                pixels[offset + 1] = color.green
                pixels[offset + 2] = color.blue
            }
        }
        guard let image = bitmapImage(columns: columns, rows: rows, pixels: pixels) else {
            return fill(classicDesktop)
        }
        let size = CGSize(width: CGFloat(columns) * dot, height: CGFloat(rows) * dot)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: CGPoint(x: 0, y: height - size.height), size: size))
    }

    // MARK: - Pebbles

    /// The classic desktop tile, repeated. Each of its 19 colors is recolored as the
    /// desktop color plus its offset from the tile's average, so the texture survives in
    /// any hue; a theme whose desktop is `#6A6AA7` shows the original colors. The seed
    /// slides and mirrors the tile.
    mutating func paintPebbles() {
        let desktop = classicDesktop
        let reference = MacintoshPebbles.reference
        let tones = MacintoshPebbles.palette.map { hex in
            Tone(
                red: desktop.red8 + Int(hex >> 16 & 0xFF) - reference.red,
                green: desktop.green8 + Int(hex >> 8 & 0xFF) - reference.green,
                blue: desktop.blue8 + Int(hex & 0xFF) - reference.blue
            )
        }
        let side = MacintoshPebbles.side
        let shiftX = rng.int(below: side), shiftY = rng.int(below: side)
        let mirrored = rng.unit() < 0.5
        paintMacPixels(tones) { column, row in
            let x = ((mirrored ? -column : column) + shiftX) % side
            let y = (row + shiftY) % side
            return Int(MacintoshPebbles.indices[(y < 0 ? y + side : y) * side + (x < 0 ? x + side : x)])
        }
    }

    // MARK: - Desktop patterns

    /// An 8×8 one-bit tile: one byte per row, the top row first, the leftmost pixel in the
    /// high bit, like the patterns of the Desktop Patterns control panel.
    struct DesktopPattern {
        let rows: [UInt8]

        func isInk(column: Int, row: Int) -> Bool {
            rows[row % 8] >> UInt8(7 - column % 8) & 1 == 1
        }
    }

    static let desktopPatterns = [
        DesktopPattern(rows: [0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55]), // checkerboard
        DesktopPattern(rows: [0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00]), // 25% dots
        DesktopPattern(rows: [0x88, 0x44, 0x22, 0x11, 0x88, 0x44, 0x22, 0x11]), // diagonals
        DesktopPattern(rows: [0xFF, 0x80, 0x80, 0x80, 0xFF, 0x08, 0x08, 0x08]), // bricks
        DesktopPattern(rows: [0x81, 0x42, 0x24, 0x18, 0x18, 0x24, 0x42, 0x81]), // diamonds
        DesktopPattern(rows: [0xFF, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80]), // plaid
        DesktopPattern(rows: [0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC]), // ticking
    ]

    /// A Desktop Patterns control panel tile repeated over the desktop color: ink and paper
    /// are the desktop toned darker (or lighter, on a dark desktop). The seed picks the tile.
    mutating func paintDesktopPattern() {
        let desktop = classicDesktop
        let ink = desktop.hsl.lightness > 0.5 ? desktop.mix(.black, 0.28) : desktop.mix(.white, 0.22)
        let pattern = Self.desktopPatterns[rng.int(below: Self.desktopPatterns.count)]
        paintMacPixels([Tone(desktop), Tone(ink)]) { column, row in
            pattern.isInk(column: column, row: row) ? 1 : 0
        }
    }

    // MARK: - Pinstripes

    /// Platinum's pinstripes: rows alternately lighter and darker than the desktop, the
    /// contrast easing along the height like a lit panel. The seed picks the stripe width.
    mutating func paintPinstripes() {
        let desktop = classicDesktop
        let thickness = 1 + rng.int(below: 2)
        // Ten steps of light and dark tone each, brightest at the top.
        let lifts = (0 ..< 10).map { step -> (light: Tone, dark: Tone) in
            let fade = Double(step) / 9
            return isDark
                ? (Tone(desktop.mix(.white, 0.07 - 0.03 * fade)), Tone(desktop.mix(.black, 0.22 + 0.16 * fade)))
                : (Tone(desktop.mix(.white, 0.34 - 0.14 * fade)), Tone(desktop.mix(.black, 0.06 + 0.1 * fade)))
        }
        let rows = Int((height / macPixel).rounded(.up))
        paintMacPixels(lifts.flatMap { [$0.light, $0.dark] }) { _, row in
            let step = min(row * lifts.count / rows, lifts.count - 1)
            return step * 2 + (row / thickness % 2)
        }
    }
}
