import AppKit

/// Generates a template NSImage for the menu bar: an angled wand with concentric waves
/// emanating from its bulb head — a monochrome echo of the app icon.
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let w = rect.width
            let h = rect.height

            // Wand geometry: bulb head slightly left-of-center so waves fit inside the bbox.
            let headCenter = CGPoint(x: w * 0.44, y: h * 0.54)
            let headRadius = min(w, h) * 0.16
            let tipCenter = CGPoint(x: w * 0.18, y: h * 0.18)
            let bodyHalfWidth = min(w, h) * 0.085

            // Draw the wand as an angled capsule using a transform on a horizontal stadium.
            let dx = tipCenter.x - headCenter.x
            let dy = tipCenter.y - headCenter.y
            let bodyLength = sqrt(dx * dx + dy * dy)
            let angle = atan2(dy, dx)

            NSColor.black.setFill()

            // Body: horizontal rounded rect from headCenter to tipCenter, then rotated.
            let bodyRect = CGRect(
                x: 0,
                y: -bodyHalfWidth,
                width: bodyLength,
                height: bodyHalfWidth * 2
            )
            let bodyPath = NSBezierPath(
                roundedRect: bodyRect,
                xRadius: bodyHalfWidth,
                yRadius: bodyHalfWidth
            )
            let transform = NSAffineTransform()
            transform.translateX(by: headCenter.x, yBy: headCenter.y)
            transform.rotate(byRadians: angle)
            bodyPath.transform(using: transform as AffineTransform)
            bodyPath.fill()

            // Bulb head — drawn last so it sits on top of the body neck.
            let head = NSBezierPath(ovalIn: CGRect(
                x: headCenter.x - headRadius,
                y: headCenter.y - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            ))
            head.fill()

            // --- Concentric waves on the upper-right of the head ---
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)

            let strokeWidth = max(1.0, min(w, h) * 0.055)
            ctx.setLineWidth(strokeWidth)

            // Three arcs sweeping the upper-right quadrant, sized to stay inside the bbox.
            let waveStart = CGFloat(-Double.pi / 10)   // -18°
            let waveEnd = CGFloat(Double.pi / 2.6)     // ~69°
            let baseRadius = headRadius + strokeWidth * 1.5
            let step = strokeWidth * 1.9

            for index in 0..<3 {
                let radius = baseRadius + step * CGFloat(index)
                ctx.beginPath()
                ctx.addArc(
                    center: headCenter,
                    radius: radius,
                    startAngle: waveStart,
                    endAngle: waveEnd,
                    clockwise: false
                )
                ctx.strokePath()
            }

            ctx.restoreGState()

            return true
        }
        image.isTemplate = true
        return image
    }
}
