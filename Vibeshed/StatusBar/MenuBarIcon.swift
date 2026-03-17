import AppKit

/// Generates a template NSImage for the menu bar: a house silhouette with a wave motif.
enum MenuBarIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let w = rect.width
            let h = rect.height

            let path = NSBezierPath()

            // --- House outline ---
            // Roof peak
            let peak = CGPoint(x: w * 0.5, y: h * 0.95)
            // Roof left
            let roofLeft = CGPoint(x: w * 0.02, y: h * 0.52)
            // Roof right
            let roofRight = CGPoint(x: w * 0.98, y: h * 0.52)
            // Walls
            let wallTopLeft = CGPoint(x: w * 0.12, y: h * 0.52)
            let wallTopRight = CGPoint(x: w * 0.88, y: h * 0.52)
            let wallBottomLeft = CGPoint(x: w * 0.12, y: h * 0.05)
            let wallBottomRight = CGPoint(x: w * 0.88, y: h * 0.05)

            // Draw the full house shape (roof + walls)
            path.move(to: wallBottomLeft)
            path.line(to: wallTopLeft)
            path.line(to: roofLeft)
            path.line(to: peak)
            path.line(to: roofRight)
            path.line(to: wallTopRight)
            path.line(to: wallBottomRight)
            path.close()

            // Clip to house shape
            path.setClip()

            // Fill house body
            NSColor.black.setFill()
            path.fill()

            // --- Wave cutout (creates the wave motif by erasing a band) ---
            let wavePath = NSBezierPath()
            let waveY: CGFloat = h * 0.45
            let amplitude: CGFloat = h * 0.12
            let bandWidth: CGFloat = h * 0.13

            // Upper wave edge
            wavePath.move(to: CGPoint(x: 0, y: waveY))
            wavePath.curve(
                to: CGPoint(x: w * 0.5, y: waveY + amplitude),
                controlPoint1: CGPoint(x: w * 0.15, y: waveY - amplitude),
                controlPoint2: CGPoint(x: w * 0.35, y: waveY + amplitude)
            )
            wavePath.curve(
                to: CGPoint(x: w, y: waveY),
                controlPoint1: CGPoint(x: w * 0.65, y: waveY + amplitude),
                controlPoint2: CGPoint(x: w * 0.85, y: waveY - amplitude)
            )

            // Lower wave edge (offset down by bandWidth)
            let lowerY = waveY - bandWidth
            wavePath.line(to: CGPoint(x: w, y: lowerY))
            wavePath.curve(
                to: CGPoint(x: w * 0.5, y: lowerY + amplitude),
                controlPoint1: CGPoint(x: w * 0.85, y: lowerY - amplitude),
                controlPoint2: CGPoint(x: w * 0.65, y: lowerY + amplitude)
            )
            wavePath.curve(
                to: CGPoint(x: 0, y: lowerY),
                controlPoint1: CGPoint(x: w * 0.35, y: lowerY + amplitude),
                controlPoint2: CGPoint(x: w * 0.15, y: lowerY - amplitude)
            )
            wavePath.close()

            // Erase the wave band from the filled house
            guard let cgContext = NSGraphicsContext.current?.cgContext else { return false }
            cgContext.setBlendMode(.clear)
            wavePath.fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
