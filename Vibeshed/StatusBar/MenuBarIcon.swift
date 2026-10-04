import AppKit

/// The menu bar glyph: the wand head-down at 150°, as in the app icon, with a vibration arc either
/// side of its head. It's a template image, so the system tints it for light, dark and highlighted
/// menu bars.
enum MenuBarIcon {
    static func make(size: CGFloat = 18, capsLockActive: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Head-down, the wand and its arcs are taller than they are wide; 0.9 fits them.
            let unit = min(rect.width, rect.height) * 0.9

            // Draw in the wand's own frame: origin at the center of the head's dome, +x running
            // down the axis toward the handle (120°: head down-right, handle up-left).
            ctx.saveGState()
            ctx.translateBy(x: rect.width * 0.507, y: rect.height * 0.374)
            ctx.rotate(by: .pi * 2 / 3)
            drawWand(unit: unit)
            drawVibration(in: ctx, unit: unit)
            ctx.restoreGState()

            if capsLockActive {
                let dotRadius = min(rect.width, rect.height) * 0.09
                let dotCenter = CGPoint(x: rect.width * 0.87, y: rect.height * 0.87)
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillEllipse(in: CGRect(
                    x: dotCenter.x - dotRadius,
                    y: dotCenter.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                ))
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    /// The wand, in its own frame: a dome-headed bulb with a flat base, a pinched neck and a
    /// capsule handle. Each part is filled on its own so the overlaps simply merge.
    private static func drawWand(unit: CGFloat) {
        let headRadius = unit * 0.19
        let baseOffset = headRadius * 0.78 // the head's flat base, measured from the dome's center
        let baseCorner = headRadius * 0.5
        let neckLength = unit * 0.1
        let neckHalfWidth = headRadius * 0.3
        let handleHalfWidth = headRadius * 0.5
        let handleStart = baseOffset + neckLength
        let handleEnd = unit * 0.72

        NSColor.black.setFill()
        NSBezierPath(
            roundedRect: CGRect(
                x: handleStart,
                y: -handleHalfWidth,
                width: handleEnd - handleStart,
                height: handleHalfWidth * 2
            ),
            xRadius: handleHalfWidth,
            yRadius: handleHalfWidth
        ).fill()
        // The neck reaches into the head and handle so there's no seam at either end.
        NSBezierPath(rect: CGRect(
            x: baseOffset - baseCorner,
            y: -neckHalfWidth,
            width: neckLength + baseCorner * 2,
            height: neckHalfWidth * 2
        )).fill()
        NSBezierPath(ovalIn: CGRect(
            x: -headRadius,
            y: -headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        )).fill()
        NSBezierPath(
            roundedRect: CGRect(
                x: -baseCorner,
                y: -headRadius,
                width: baseOffset + baseCorner,
                height: headRadius * 2
            ),
            xRadius: baseCorner,
            yRadius: baseCorner
        ).fill()
    }

    /// One arc on each side of the head, square to the wand's axis.
    private static func drawVibration(in ctx: CGContext, unit: CGFloat) {
        let radius = unit * 0.35
        let sweep = CGFloat.pi / 5.3 // ~34° either way

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineCap(.round)
        ctx.setLineWidth(max(1, unit * 0.095))

        for side in [CGFloat.pi / 2, -CGFloat.pi / 2] {
            ctx.beginPath()
            ctx.addArc(
                center: .zero,
                radius: radius,
                startAngle: side - sweep,
                endAngle: side + sweep,
                clockwise: false
            )
            ctx.strokePath()
        }

        ctx.restoreGState()
    }
}
