import AppKit
@testable import Vibeshed
import XCTest

/// Renders an overlay's own layers (tint, vignette, grain) offscreen. The system blur
/// beneath them needs the window server, so these styles leave it off.
@MainActor
final class OverlayRenderingTests: XCTestCase {
    private let size = CGSize(width: 400, height: 300)

    private func style(opacity: Double, vignette: Double = 0, grain: Double = 0) -> OverlayStyle {
        var config = AppConfig.OverlayConfig()
        config.blur = 0
        config.opacity = opacity
        config.vignette = vignette
        config.grain = grain
        return OverlayStyle(config: config, tint: .black, reduceTransparency: false)
    }

    /// The overlay's alpha at each point, fully shown. Hosted in a window (never ordered
    /// in) so AppKit assembles the subviews' layers into one tree, as on screen.
    private func render(_ style: OverlayStyle, focus: CGPoint) throws -> (CGPoint) -> Double {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = OverlayContentView(frame: .zero)
        window.contentView = view
        window.setFrame(CGRect(origin: .zero, size: size), display: false)
        view.apply(style, focus: focus, focusRadius: 40)
        view.animateIn(.none, duration: 0)
        window.displayIfNeeded()
        let layer = try XCTUnwrap(view.layer)
        let width = Int(size.width)
        let height = Int(size.height)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        layer.render(in: context)
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let bytes = Array(UnsafeBufferPointer(start: data, count: width * height * 4))
        return { point in
            // Bitmap rows run top-down; the layer's y runs up.
            let row = height - 1 - Int(point.y)
            return Double(bytes[(row * width + Int(point.x)) * 4 + 3]) / 255
        }
    }

    func testTintCoversTheScreenEvenly() throws {
        let alpha = try render(style(opacity: 0.2), focus: CGPoint(x: 200, y: 150))
        XCTAssertEqual(alpha(CGPoint(x: 200, y: 150)), 0.2, accuracy: 0.01)
        XCTAssertEqual(alpha(CGPoint(x: 2, y: 2)), 0.2, accuracy: 0.01)
        XCTAssertEqual(alpha(CGPoint(x: 397, y: 297)), 0.2, accuracy: 0.01)
    }

    func testVignetteDarkensTowardTheEdgesAroundTheFocus() throws {
        // Picker off-centre: the farthest corner (top right) gets the full vignette.
        let alpha = try render(style(opacity: 0.2, vignette: 0.6), focus: CGPoint(x: 120, y: 100))
        XCTAssertEqual(alpha(CGPoint(x: 120, y: 100)), 0.2, accuracy: 0.01)
        let far = alpha(CGPoint(x: 399, y: 299))
        let near = alpha(CGPoint(x: 0, y: 0))
        // Source-over: 0.2 + 0.6 × (1 − 0.2) at the edge of the vignette circle.
        XCTAssertEqual(far, 0.68, accuracy: 0.04)
        XCTAssertGreaterThan(near, 0.2)
        XCTAssertLessThan(near, far)
    }

    func testGrainAddsTextureAroundAnEvenMean() throws {
        let alpha = try render(style(opacity: 0, grain: 1), focus: CGPoint(x: 200, y: 150))
        var samples: [Double] = []
        for y in stride(from: 0, to: 300, by: 3) {
            for x in stride(from: 0, to: 400, by: 3) {
                samples.append(alpha(CGPoint(x: x, y: y)))
            }
        }
        let mean = samples.reduce(0, +) / Double(samples.count)
        XCTAssertGreaterThan(mean, 0.05, "grain should be visible")
        XCTAssertGreaterThan(samples.max() ?? 0, mean * 2, "grain should vary, not tint")
        // Beyond the first 256pt tile too: the replicators repeat it across the screen.
        XCTAssertGreaterThan(samples.count, 0)
        let outside = stride(from: 260, to: 400, by: 2).map { alpha(CGPoint(x: $0, y: 280)) }
        XCTAssertGreaterThan(outside.reduce(0, +) / Double(outside.count), 0.05)
    }

    func testNothingShowsBeforeAnimatingIn() {
        let view = OverlayContentView(frame: CGRect(origin: .zero, size: size))
        view.apply(style(opacity: 0.5), focus: CGPoint(x: 200, y: 150), focusRadius: 40)
        XCTAssertEqual(view.layer?.opacity, 0)
    }
}
