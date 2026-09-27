import CoreGraphics
import Foundation

/// Unit space, where the generative styles draw: the canvas is 1000 units tall at any
/// resolution (so a style reads the same in a thumbnail and on a 6K display), the origin
/// is the top-left corner and y points down — the layout of the canvas prototypes the
/// styles were designed in.
extension WallpaperCanvas {
    var unitHeight: CGFloat { 1000 }
    var unitWidth: CGFloat { width / unit }

    /// Switches the context to unit space for the rest of the style. The renderer saves
    /// the graphics state around every style, so there's nothing to undo.
    func enterUnitSpace() {
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: unit, y: -unit)
    }

    /// A line width in units that never thins below `pixels` device pixels, so hairlines
    /// still show in small thumbnails.
    func hairline(_ units: CGFloat, minimum pixels: CGFloat = 1) -> CGFloat {
        max(units, pixels / unit)
    }

    /// An opaque RGBX bitmap, row 0 at the top, for styles that compute pixels.
    func bitmapImage(columns: Int, rows: Int, pixels: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}

extension ThemeColor {
    func cgColor(alpha: Double) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

extension CGPoint {
    /// The point `amount` of the way toward `other`.
    func interpolated(to other: CGPoint, _ amount: CGFloat) -> CGPoint {
        CGPoint(x: x + (other.x - x) * amount, y: y + (other.y - y) * amount)
    }
}

extension Array {
    /// The element at `index`, wrapping around — for palettes with fewer hues than asked for.
    func cycling(_ index: Int) -> Element {
        self[(index % count + count) % count]
    }
}

/// Hermite step from 0 at `edge0` to 1 at `edge1`.
func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
    let progress = min(max((value - edge0) / (edge1 - edge0), 0), 1)
    return progress * progress * (3 - 2 * progress)
}
