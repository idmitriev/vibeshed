import AppKit
import CoreGraphics
import Foundation

enum ColorExtractor {
    private static var cache: [String: (dominant: NSColor, vibrant: NSColor)] = [:]

    static func extractColors(
        from urlString: String
    ) async -> (dominant: NSColor, vibrant: NSColor)? {
        if let cached = cache[urlString] { return cached }

        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data),
              let cgImage = image.cgImage(
                  forProposedRect: nil, context: nil, hints: nil
              ),
              let pixels = rasterize(cgImage)
        else { return nil }

        let result = analyzePixels(pixels)
        cache[urlString] = result
        return result
    }

    /// Synchronous extraction from a CGImage (e.g. screen capture, wallpaper).
    static func extractColors(
        from cgImage: CGImage
    ) -> (dominant: NSColor, vibrant: NSColor)? {
        guard let pixels = rasterize(cgImage) else { return nil }
        return analyzePixels(pixels)
    }

    static func clearCache() {
        cache.removeAll()
    }

    // MARK: - Internal

    static let thumbSize = 16

    static func rasterize(_ cgImage: CGImage) -> [UInt8]? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let byteCount = thumbSize * thumbSize * 4
        guard let ctx = CGContext(
            data: nil, width: thumbSize, height: thumbSize,
            bitsPerComponent: 8, bytesPerRow: thumbSize * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }

        ctx.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize)
        )
        guard let data = ctx.data else { return nil }
        // Copy pixel data out before CGContext is deallocated
        let ptr = data.bindMemory(
            to: UInt8.self, capacity: byteCount
        )
        return Array(UnsafeBufferPointer(start: ptr, count: byteCount))
    }

    static func analyzePixels(
        _ buffer: [UInt8]
    ) -> (dominant: NSColor, vibrant: NSColor) {
        var totalRed = 0.0, totalGreen = 0.0, totalBlue = 0.0
        var bestScore = 0.0
        var vibRed = 0.0, vibGreen = 0.0, vibBlue = 0.0
        let pixelCount = thumbSize * thumbSize

        for idx in 0..<pixelCount {
            let offset = idx * 4
            let red = Double(buffer[offset]) / 255.0
            let green = Double(buffer[offset + 1]) / 255.0
            let blue = Double(buffer[offset + 2]) / 255.0

            totalRed += red
            totalGreen += green
            totalBlue += blue

            let maxC = max(red, green, blue)
            let minC = min(red, green, blue)
            let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
            let score = saturation * (0.5 + maxC * 0.5)

            if score > bestScore {
                bestScore = score
                vibRed = red
                vibGreen = green
                vibBlue = blue
            }
        }

        let count = Double(pixelCount)
        let dominant = NSColor(
            red: totalRed / count,
            green: totalGreen / count,
            blue: totalBlue / count,
            alpha: 1
        )

        let vibrant: NSColor
        if bestScore > 0.1 {
            vibrant = NSColor(
                red: vibRed, green: vibGreen, blue: vibBlue, alpha: 1
            )
        } else {
            vibrant = dominant
        }

        return (dominant: dominant, vibrant: vibrant)
    }
}
