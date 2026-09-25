import AppKit
import SwiftUI

/// An opaque sRGB color with components in `0...1` — the theme system's lingua franca.
/// Parsed from `#rrggbb` config strings, mixed and derived by `ThemePalette`, then
/// rendered into every target's format (hex, `r,g,b`, 16-bit AppleScript triples,
/// `NSColor`, SwiftUI `Color`).
struct ThemeColor: Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    /// Components are clamped and quantized to 8 bits, so every color — parsed or
    /// derived — survives a hex round trip unchanged (and derived shades match Omarchy,
    /// which rounds at every step too).
    init(red: Double, green: Double, blue: Double) {
        self.red = Self.quantize(red)
        self.green = Self.quantize(green)
        self.blue = Self.quantize(blue)
    }

    private static func quantize(_ component: Double) -> Double {
        Double(byte(min(max(component, 0), 1))) / 255
    }

    /// Accepts `#rgb`, `#rrggbb` and `#rrggbbaa` (alpha is dropped), with or without `#`.
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        if cleaned.count == 3 {
            cleaned = cleaned.map { "\($0)\($0)" }.joined()
        }
        if cleaned.count == 8 { cleaned = String(cleaned.prefix(6)) }
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    init?(nsColor: NSColor) {
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent)
    }

    static let white = ThemeColor(red: 1, green: 1, blue: 1)
    static let black = ThemeColor(red: 0, green: 0, blue: 0)

    // MARK: - Formats

    // Round half up like Omarchy's `int(x + 0.5)`; the epsilon absorbs float error on
    // exact halves (26 × 0.75 = 19.5 must not come out as 19.4999…).
    var red8: Int { Self.byte(red) }
    var green8: Int { Self.byte(green) }
    var blue8: Int { Self.byte(blue) }

    private static func byte(_ component: Double) -> Int {
        Int(component * 255 + 0.5 + 1e-9)
    }

    /// `#rrggbb`, lowercase.
    var hex: String {
        String(format: "#%02x%02x%02x", red8, green8, blue8)
    }

    /// `rrggbb` — the `_strip` template form, and JetBrains' scheme format.
    var hexStripped: String {
        String(hex.dropFirst())
    }

    /// `r,g,b` with 0–255 components — the `_rgb` template form.
    var rgbString: String {
        "\(red8),\(green8),\(blue8)"
    }

    /// `{r, g, b}` with 16-bit components, as AppleScript color properties expect.
    var appleScriptList: String {
        "{\(Int(red * 65535)), \(Int(green * 65535)), \(Int(blue * 65535))}"
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    // MARK: - Mixing

    /// Linear blend toward `other`: `amount` 0 returns `self`, 1 returns `other`.
    func mix(_ other: ThemeColor, _ amount: Double) -> ThemeColor {
        let amount = min(max(amount, 0), 1)
        return ThemeColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    func lightened(_ amount: Double) -> ThemeColor {
        mix(.white, amount)
    }

    func darkened(_ amount: Double) -> ThemeColor {
        mix(.black, amount)
    }

    // MARK: - Perception

    /// WCAG 2 relative luminance.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2 contrast ratio, 1…21.
    func contrastRatio(with other: ThemeColor) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Mirrors Omarchy's light-theme detection (`r + g + b > 382`), so a palette
    /// ported from an Omarchy `colors.toml` lands in the same mode.
    var isLight: Bool {
        red8 + green8 + blue8 > 382
    }

    /// Black or white, whichever reads better on top of this color.
    var contrastingText: ThemeColor {
        contrastRatio(with: .white) >= contrastRatio(with: .black) ? .white : .black
    }

    // MARK: - HSL

    /// Hue in degrees `0..<360`; saturation and lightness in `0...1`.
    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxC = max(red, green, blue)
        let minC = min(red, green, blue)
        let lightness = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 0.000_01 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double = if maxC == red {
            60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == green {
            60 * ((blue - red) / delta + 2)
        } else {
            60 * ((red - green) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        return (hue, min(saturation, 1), lightness)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let hue = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let saturation = min(max(saturation, 0), 1)
        let lightness = min(max(lightness, 0), 1)
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let secondary = chroma * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2
        let (red, green, blue): (Double, Double, Double) = switch hue {
        case 0 ..< 60: (chroma, secondary, 0)
        case 60 ..< 120: (secondary, chroma, 0)
        case 120 ..< 180: (0, chroma, secondary)
        case 180 ..< 240: (0, secondary, chroma)
        case 240 ..< 300: (secondary, 0, chroma)
        default: (chroma, 0, secondary)
        }
        self.init(red: red + match, green: green + match, blue: blue + match)
    }

    /// Shortest angular distance between two hues, `0...180`.
    static func hueDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let diff = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(diff, 360 - diff)
    }
}

// MARK: - Codable (as a hex string)

extension ThemeColor: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = ThemeColor(hex: string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid hex color '\(string)'"
            )
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
