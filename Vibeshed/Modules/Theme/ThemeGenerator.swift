import AppKit
import CoreGraphics

/// Derives a complete palette from an image, in the spirit of Aether: a background and
/// foreground tinted by the image's dominant tone, its most vivid color as the accent,
/// and each ANSI hue pulled toward whatever the image actually has near that hue — so
/// the terminal, editor and system accents all feel like they belong to the wallpaper.
enum ThemeGenerator {
    static let generatedName = "From Wallpaper"

    /// Target hue (degrees) for each semantic color.
    private static let hueTargets: [(key: String, hue: Double)] = [
        ("red", 355), ("orange", 25), ("yellow", 45), ("green", 115),
        ("cyan", 180), ("blue", 218), ("magenta", 295),
    ]

    private struct Sample {
        let hue: Double
        let saturation: Double
        let lightness: Double
    }

    /// Returns raw `colors.toml`-style keys (hex values plus `mode`), or nil if the image
    /// can't be read.
    static func palette(from image: CGImage, mode requestedMode: ThemeMode? = nil) -> [String: String]? {
        guard let samples = sample(image), !samples.isEmpty else { return nil }

        let averageLightness = samples.map(\.lightness).reduce(0, +) / Double(samples.count)
        let mode = requestedMode ?? (averageLightness > 0.62 ? .light : .dark)
        let isDark = mode == .dark

        let saturations = samples.map(\.saturation).sorted()
        let vibrancy = saturations[Int(Double(saturations.count - 1) * 0.75)]
        let hueSaturation = min(max(vibrancy, 0.45), 0.78)
        let hueLightness = isDark ? 0.68 : 0.42

        // Background: the image's darkest (dark mode) or lightest (light mode) tone.
        let byLightness = samples.sorted { $0.lightness < $1.lightness }
        let toneSlice = isDark ? byLightness.prefix(byLightness.count / 3) : byLightness.suffix(byLightness.count / 3)
        let toneHue = circularMeanHue(Array(toneSlice), weightedBySaturation: true) ?? 230
        let toneSaturation = min((toneSlice.map(\.saturation).reduce(0, +) / Double(max(toneSlice.count, 1))), 0.35)

        let background = ThemeColor(hue: toneHue, saturation: toneSaturation * 0.6, lightness: isDark ? 0.1 : 0.95)
        let foreground = ThemeColor(hue: toneHue, saturation: 0.18, lightness: isDark ? 0.86 : 0.2)
        let accent = mostVivid(samples).map {
            ThemeColor(hue: $0.hue, saturation: max($0.saturation, 0.5), lightness: isDark ? 0.66 : 0.45)
        } ?? ThemeColor(hue: 218, saturation: hueSaturation, lightness: hueLightness)

        var colors: [String: ThemeColor] = [
            "background": background,
            "foreground": foreground,
            "bright_foreground": ThemeColor(hue: toneHue, saturation: 0.12, lightness: isDark ? 0.94 : 0.1),
            "accent": accent,
            "muted": ThemeColor(hue: toneHue, saturation: 0.12, lightness: isDark ? 0.45 : 0.55),
            "selection_background": background.mix(accent, 0.3),
            "lighter_background": background.mix(foreground, 0.08),
        ]
        for target in hueTargets {
            let hue = nearbyHue(target.hue, in: samples) ?? target.hue
            colors[target.key] = ThemeColor(hue: hue, saturation: hueSaturation, lightness: hueLightness)
            colors["bright_\(target.key)"] = ThemeColor(
                hue: hue,
                saturation: min(hueSaturation + 0.05, 1),
                lightness: hueLightness + (isDark ? 0.08 : -0.06)
            )
        }

        var raw = colors.mapValues(\.hex)
        raw["mode"] = mode.rawValue
        return raw
    }

    /// Reads the wallpaper of the main screen.
    @MainActor
    static func currentWallpaperImage() -> CGImage? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url)
        else { return nil }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    // MARK: - Sampling

    private static let sampleSize = 48

    private static func sample(_ image: CGImage) -> [Sample]? {
        let size = sampleSize
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return nil }
        let bytes = data.bindMemory(to: UInt8.self, capacity: size * size * 4)

        return (0 ..< size * size).map { index in
            let offset = index * 4
            let color = ThemeColor(
                red: Double(bytes[offset]) / 255,
                green: Double(bytes[offset + 1]) / 255,
                blue: Double(bytes[offset + 2]) / 255
            )
            let hsl = color.hsl
            return Sample(hue: hsl.hue, saturation: hsl.saturation, lightness: hsl.lightness)
        }
    }

    /// The most saturated mid-lightness sample (very dark/light pixels have unreliable hue).
    private static func mostVivid(_ samples: [Sample]) -> Sample? {
        samples
            .filter { $0.lightness > 0.2 && $0.lightness < 0.85 }
            .max { score($0) < score($1) }
            .flatMap { score($0) > 0.2 ? $0 : nil }
    }

    private static func score(_ sample: Sample) -> Double {
        sample.saturation * (1 - abs(sample.lightness - 0.55) * 1.2)
    }

    /// The image's own hue near `target` (±28°), if it has enough color there. Pulled
    /// halfway toward the target so red stays red even in an orange-heavy image.
    private static func nearbyHue(_ target: Double, in samples: [Sample]) -> Double? {
        let nearby = samples.filter {
            $0.saturation > 0.25 && $0.lightness > 0.15 && $0.lightness < 0.9
                && ThemeColor.hueDistance($0.hue, target) <= 28
        }
        guard nearby.count >= samples.count / 100 + 1,
              let mean = circularMeanHue(nearby, weightedBySaturation: true)
        else { return nil }
        return circularMean([(mean, 1), (target, 1)])
    }

    private static func circularMeanHue(_ samples: [Sample], weightedBySaturation: Bool) -> Double? {
        circularMean(samples.map { ($0.hue, weightedBySaturation ? $0.saturation : 1) })
    }

    private static func circularMean(_ values: [(hue: Double, weight: Double)]) -> Double? {
        var sinSum = 0.0
        var cosSum = 0.0
        for value in values {
            let radians = value.hue * .pi / 180
            sinSum += sin(radians) * value.weight
            cosSum += cos(radians) * value.weight
        }
        guard abs(sinSum) + abs(cosSum) > 0.000_1 else { return nil }
        let degrees = atan2(sinSum, cosSum) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}
