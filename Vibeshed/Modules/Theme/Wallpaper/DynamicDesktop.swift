import Foundation
import ImageIO

/// macOS dynamic desktops: one `.heic` holding a light and a dark picture (`apr`, e.g. the
/// "hello" wallpapers) or one per sun position (`solar`), described by a base64 property
/// list in the `apple_desktop` XMP namespace. The first image is the light/daytime one, so
/// reading such a file naively gets a picture that isn't on screen in dark mode.
enum DynamicDesktop {
    /// The image macOS shows for the given appearance, or nil when `source` isn't a
    /// dynamic desktop. Uses the file's light/dark pair (`apr`, or `ap` inside `solar` /
    /// `h24`); sun-position files without one get the highest sun for light, lowest for dark.
    static func imageIndex(in source: CGImageSource, dark: Bool) -> Int? {
        let count = CGImageSourceGetCount(source)
        guard count > 1, let metadata = CGImageSourceCopyMetadataAtIndex(source, primaryIndex(of: source), nil)
        else { return nil }

        let index: Int? = if let pair = descriptor("apr", in: metadata) {
            appearanceIndex(pair, dark: dark)
        } else if let solar = descriptor("solar", in: metadata) {
            (solar["ap"] as? [String: Any]).flatMap { appearanceIndex($0, dark: dark) }
                ?? sunIndex(solar, dark: dark)
        } else {
            (descriptor("h24", in: metadata)?["ap"] as? [String: Any]).flatMap { appearanceIndex($0, dark: dark) }
        }
        return index.flatMap { (0 ..< count).contains($0) ? $0 : nil }
    }

    /// What `url` shows in the given appearance, downsampled to at most `maxPixelSize` on its
    /// longest side; `followsAppearance` when that depends on the appearance.
    static func thumbnail(of url: URL, dark: Bool, maxPixelSize: Int) -> (image: CGImage, followsAppearance: Bool)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let dynamicIndex = imageIndex(in: source, dark: dark)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, dynamicIndex ?? primaryIndex(of: source), options)
        else { return nil }
        return (image, dynamicIndex != nil)
    }

    private static func primaryIndex(of source: CGImageSource) -> Int {
        let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        return (properties?[kCGImagePropertyPrimaryImage] as? NSNumber)?.intValue ?? 0
    }

    private static func descriptor(_ name: String, in metadata: CGImageMetadata) -> [String: Any]? {
        guard let base64 = CGImageMetadataCopyStringValueWithPath(metadata, nil, "apple_desktop:\(name)" as CFString),
              let data = Data(base64Encoded: base64 as String)
        else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// `{l: <light index>, d: <dark index>}`.
    private static func appearanceIndex(_ pair: [String: Any], dark: Bool) -> Int? {
        (pair[dark ? "d" : "l"] as? NSNumber)?.intValue
    }

    /// `si` lists each image's sun position: `{i: <index>, a: <altitude°>, z: <azimuth°>}`.
    private static func sunIndex(_ solar: [String: Any], dark: Bool) -> Int? {
        let positions = (solar["si"] as? [[String: Any]] ?? []).compactMap { entry -> (index: Int, altitude: Double)? in
            guard let index = (entry["i"] as? NSNumber)?.intValue,
                  let altitude = (entry["a"] as? NSNumber)?.doubleValue
            else { return nil }
            return (index, altitude)
        }
        let pick = dark
            ? positions.min { $0.altitude < $1.altitude }
            : positions.max { $0.altitude < $1.altitude }
        return pick?.index
    }
}
