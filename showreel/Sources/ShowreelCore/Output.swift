import Foundation

public enum OutputFormat: String, Codable, Sendable {
    case mp4
    case webm
    case gif
    /// ProRes, for editing.
    case mov
    /// A single frame, picked with `at`.
    case png

    public var isVideo: Bool { self != .png }
}

/// How a crop is fitted into an output `size` of a different shape.
public enum Fit: String, Codable, Sendable {
    /// Scale to fit inside and fill the rest with `background`.
    case pad
    /// Scale to fill and cut off what sticks out.
    case cover
}

/// The part of the recording an output shows.
public enum Crop: Sendable, Equatable {
    case display
    case region(RegionTarget)
}

/// Output pixel size, written `1080x1920`.
public struct PixelSize: Decodable, Sendable, Equatable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts.allSatisfy({ $0 > 0 }) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "expected WIDTHxHEIGHT, got '\(text)'"
            ))
        }
        self.init(width: parts[0], height: parts[1])
    }
}

/// A file cut from a take on the host, e.g. a square clip for social media:
///
/// ```yaml
/// - name: square
///   crop: picker
///   padding: 120
///   size: 1080x1080
///   background: blur
///   from: opened-0.5
/// ```
public struct OutputSpec: Decodable, Sendable {
    public var name: String
    public var format = OutputFormat.mp4
    /// `display`, `picker`, an app's window, or `[x, y, width, height]` in points.
    public var crop = Crop.display
    /// Points added around the crop.
    public var padding = 0.0
    /// Exact output size; the crop is fitted into it with `fit`.
    public var size: PixelSize?
    /// Output width with the crop's aspect ratio, when `size` isn't given.
    public var width: Int?
    public var fit = Fit.pad
    /// Fill for `fit: pad`: an ffmpeg color (`black`, `#101018`) or `blur`
    /// for a blurred, zoomed copy of the clip.
    public var background = "black"
    public var fps: Int?
    public var from: TimeRef?
    public var to: TimeRef?
    /// The frame a `png` output shows.
    public var at: TimeRef?
    public var speed = 1.0
    /// Seconds of crossfade from the clip's end back into its start, for
    /// `<video loop>`: the output is that much shorter and cycles seamlessly.
    /// Leave that long of a still moment at the start of the clip.
    public var loop: Double?
    /// Stretches cut out of the clip, e.g. `[[searching+0.5, results]]` to
    /// jump past a spinner.
    public var skip: [[TimeRef]] = []
    /// Encoder quality: CRF for mp4 (default 18) and webm (default 32).
    public var quality: Int?
    /// Seconds a video opens on a before/after frame: the left half of its first frame
    /// beside the right half of its last. A `<name>-split.png` of it is written too.
    public var beforeAfter: Double?

    enum CodingKeys: String, CodingKey {
        case name, format, crop, padding, size, width, fit, background, fps, from, to, at, speed, loop, skip, quality
        case beforeAfter
    }

    public init(name: String) {
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        format = try container.decodeIfPresent(OutputFormat.self, forKey: .format) ?? format
        if let rect = try? container.decode(Rect.self, forKey: .crop) {
            crop = .region(.rect(rect))
        } else if let target = try container.decodeIfPresent(String.self, forKey: .crop) {
            crop = target == "display" ? .display : .region(.window(WindowTarget(target)))
        }
        padding = try container.decodeIfPresent(Double.self, forKey: .padding) ?? padding
        size = try container.decodeIfPresent(PixelSize.self, forKey: .size)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        fit = try container.decodeIfPresent(Fit.self, forKey: .fit) ?? fit
        background = try container.decodeIfPresent(String.self, forKey: .background) ?? background
        fps = try container.decodeIfPresent(Int.self, forKey: .fps)
        from = try container.decodeIfPresent(TimeRef.self, forKey: .from)
        to = try container.decodeIfPresent(TimeRef.self, forKey: .to)
        at = try container.decodeIfPresent(TimeRef.self, forKey: .at)
        speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? speed
        loop = try container.decodeIfPresent(Double.self, forKey: .loop)
        skip = try container.decodeIfPresent([[TimeRef]].self, forKey: .skip) ?? []
        if skip.contains(where: { $0.count != 2 }) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath + [CodingKeys.skip], debugDescription: "each skip is [from, to]"
            ))
        }
        quality = try container.decodeIfPresent(Int.self, forKey: .quality)
        beforeAfter = try container.decodeIfPresent(Double.self, forKey: .beforeAfter)
        if format == .png, at == nil {
            throw DecodingError.keyNotFound(CodingKeys.at, .init(
                codingPath: container.codingPath, debugDescription: "a png output needs `at`"
            ))
        }
    }

    public var fileName: String { "\(name).\(format.rawValue)" }
}
