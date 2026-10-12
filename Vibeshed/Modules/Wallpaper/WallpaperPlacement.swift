import CoreGraphics
import Foundation
import ImageIO

/// How a downloaded image goes on the desktop.
enum WallpaperPlacement: Sendable, Equatable {
    /// Cover the screen, cropping what doesn't fit.
    case fill
    /// The whole image, on a background of `matte`.
    case fit(matte: ThemeColor)

    /// Artwork whose shape is within this factor of the screen's fills it: the crop
    /// is a sliver. Anything further off would lose part of the picture.
    static let fillTolerance = 1.12

    /// What the choice needs from a downloaded image, read once for every screen.
    struct Image: Sendable, Equatable {
        let aspectRatio: Double?
        let matte: ThemeColor

        /// Reads `file`. The edge color is only worked out when it can be used.
        init(_ file: URL, source: WallpaperSourceID, scaling: WallpaperScaling) {
            aspectRatio = WallpaperPlacement.aspectRatio(of: file)
            let mayFit = scaling == .fit || (scaling == .auto && source.isArtwork)
            matte = mayFit ? WallpaperPlacement.edgeColor(of: file) ?? .black : .black
        }
    }

    /// The placement on one screen. Screens are decided one by one, so a landscape
    /// painting can fill a landscape display and sit on a matte on a portrait one.
    static func choose(
        for image: Image,
        source: WallpaperSourceID,
        scaling: WallpaperScaling,
        screenAspectRatio: Double
    ) -> WallpaperPlacement {
        switch scaling {
        case .fill:
            return .fill
        case .fit:
            return .fit(matte: image.matte)
        case .auto:
            guard source.isArtwork, let aspectRatio = image.aspectRatio else { return .fill }
            let mismatch = max(aspectRatio, screenAspectRatio) / min(aspectRatio, screenAspectRatio)
            return mismatch <= fillTolerance ? .fill : .fit(matte: image.matte)
        }
    }

    /// Width / height as displayed (EXIF rotation applied).
    static func aspectRatio(of file: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else { return nil }
        // Orientations 5–8 turn the image a quarter.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? height / width : width / height
    }

    /// The average color of the image's outer edge, so the matte continues it: dark
    /// around an old master, paper white around a watercolor.
    static func edgeColor(of file: URL) -> ThemeColor? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return edgeColor(of: thumbnail)
    }

    static func edgeColor(of image: CGImage) -> ThemeColor? {
        let width = image.width
        let height = image.height
        guard width > 2, height > 2,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // The two outermost rings of pixels.
        let ring = 2
        var sums = (red: 0, green: 0, blue: 0)
        var count = 0
        for y in 0 ..< height {
            for x in 0 ..< width
                where x < ring || y < ring || x >= width - ring || y >= height - ring
            {
                let offset = (y * width + x) * 4
                sums.red += Int(pixels[offset])
                sums.green += Int(pixels[offset + 1])
                sums.blue += Int(pixels[offset + 2])
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let scale = 255 * Double(count)
        return ThemeColor(
            red: Double(sums.red) / scale, green: Double(sums.green) / scale, blue: Double(sums.blue) / scale
        )
    }
}
