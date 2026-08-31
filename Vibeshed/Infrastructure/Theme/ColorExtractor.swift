import AppKit
import CoreGraphics
import Foundation

/// Memoizes artwork extraction by URL. Kept on its own actor rather than on the
/// main actor so `rasterize`/`analyzePixels` stay off the main thread.
private actor ArtworkColorCache {
    static let shared = ArtworkColorCache()

    private var storage: [String: (dominant: NSColor, vibrant: NSColor)] = [:]

    func colors(for key: String) -> (dominant: NSColor, vibrant: NSColor)? {
        storage[key]
    }

    func store(_ colors: (dominant: NSColor, vibrant: NSColor), for key: String) {
        storage[key] = colors
    }

    func removeAll() {
        storage.removeAll()
    }
}

enum ColorExtractor {
    static func extractColors(
        from urlString: String
    ) async -> (dominant: NSColor, vibrant: NSColor)? {
        if let cached = await ArtworkColorCache.shared.colors(for: urlString) {
            return cached
        }

        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data),
              let cgImage = image.cgImage(
                  forProposedRect: nil, context: nil, hints: nil
              ),
              let pixels = rasterize(cgImage)
        else { return nil }

        let result = analyzePixels(pixels)
        await ArtworkColorCache.shared.store(result, for: urlString)
        return result
    }

    /// Synchronous extraction from a CGImage (e.g. screen capture, wallpaper).
    static func extractColors(
        from cgImage: CGImage
    ) -> (dominant: NSColor, vibrant: NSColor)? {
        guard let pixels = rasterize(cgImage) else { return nil }
        return analyzePixels(pixels)
    }

    static func clearCache() async {
        await ArtworkColorCache.shared.removeAll()
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

        for idx in 0 ..< pixelCount {
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

        let vibrant: NSColor = if bestScore > 0.1 {
            NSColor(
                red: vibRed, green: vibGreen, blue: vibBlue, alpha: 1
            )
        } else {
            dominant
        }

        return (dominant: dominant, vibrant: vibrant)
    }
}
