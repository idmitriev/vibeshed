import CoreGraphics
import Foundation

/// What an overlay draws: its config with the theme color and accessibility settings
/// resolved.
struct OverlayStyle: Equatable {
    var blur: Double
    var saturation: Double
    var material: OverlayMaterial
    var tint: ThemeColor
    var opacity: Double
    var vignette: Double
    var grain: Double

    /// Reduce Transparency drops the blur and material; the tint still dims the screen.
    init(config: AppConfig.OverlayConfig, tint: ThemeColor, reduceTransparency: Bool) {
        blur = reduceTransparency ? 0 : config.blur
        saturation = config.saturation
        material = reduceTransparency ? .none : config.material
        self.tint = tint
        opacity = config.opacity
        vignette = config.vignette
        grain = config.grain
    }

    /// Whether the system backdrop is needed at all: for blur, or a material's tint.
    var usesBackdrop: Bool {
        blur > 0 || material != .none
    }

    /// Resolves `color`: `theme` follows the palette theme's darkest background, or the
    /// Dark/Light Mode base color without one.
    static func tint(
        for color: OverlayColor,
        palette: ThemePalette?,
        accent: ThemeColor,
        isDarkAppearance: Bool
    ) -> ThemeColor {
        switch color {
        case let .fixed(color):
            color
        case .accent:
            accent
        case .theme:
            palette?.darkerBackground ?? (isDarkAppearance ? .black : .white)
        }
    }
}

extension ThemeColor {
    func cgColor(alpha: Double) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// Circle geometry for the vignette and the iris, in a screen-sized view's coordinates.
enum OverlayGeometry {
    /// Distance from `focus` to the farthest corner — a circle this big covers the view.
    static func coverRadius(from focus: CGPoint, in size: CGSize) -> CGFloat {
        hypot(max(focus.x, size.width - focus.x), max(focus.y, size.height - focus.y))
    }

    /// Unit-space start/end points that make a radial `CAGradientLayer` spanning `size`
    /// draw a circle of `radius` around `focus` (its end point sets the x and y radii).
    static func radialPoints(
        focus: CGPoint,
        radius: CGFloat,
        in size: CGSize
    ) -> (start: CGPoint, end: CGPoint) {
        guard size.width > 0, size.height > 0 else {
            return (CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1))
        }
        let start = CGPoint(x: focus.x / size.width, y: focus.y / size.height)
        let end = CGPoint(x: start.x + radius / size.width, y: start.y + radius / size.height)
        return (start, end)
    }
}

/// The overlay's film grain, as a tile repeated across the screen.
enum OverlayGrain {
    /// Tile edge in pixels, drawn at one pixel per point.
    static let tileSize = 256

    @MainActor static let tile = makeTile(size: tileSize, seed: 0x5EED)

    /// Every pixel is white or black with an alpha drawn from a triangular distribution
    /// around zero, so the grain adds texture without shifting the average brightness.
    /// Seeded, so the grain never changes between launches.
    static func makeTile(size: Int, seed: UInt64, maxAlpha: Double = 0.45) -> CGImage? {
        var generator = SeededGenerator(seed: seed)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for pixel in 0 ..< size * size {
            let offset = generator.unit() + generator.unit() - 1
            let alpha = UInt8(min(abs(offset), 1) * maxAlpha * 255)
            // Premultiplied: white is (a, a, a, a), black is (0, 0, 0, a).
            let value = offset > 0 ? alpha : 0
            pixels[pixel * 4] = value
            pixels[pixel * 4 + 1] = value
            pixels[pixel * 4 + 2] = value
            pixels[pixel * 4 + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: size,
            height: size,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: size * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
