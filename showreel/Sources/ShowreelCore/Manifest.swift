import Foundation

/// What a take produced, written by the agent next to the recording and read
/// by the host to cut outputs. Times are seconds from the recording's start.
public struct Manifest: Codable, Sendable {
    public struct Display: Codable, Sendable {
        /// Size in points.
        public var width: Double
        public var height: Double
        /// Pixels per point.
        public var scale: Double

        public init(width: Double, height: Double, scale: Double) {
            self.width = width
            self.height = height
            self.scale = scale
        }

        public var bounds: Rect { Rect(x: 0, y: 0, width: width, height: height) }
    }

    public struct Event: Codable, Sendable {
        public var time: Double
        public var text: String

        public init(time: Double, text: String) {
            self.time = time
            self.text = text
        }
    }

    /// One stretch of video between `recording: pause`s, in its own file.
    public struct Segment: Codable, Sendable, Equatable {
        public var file: String
        /// Seconds of recording time it covers. Its file can be shorter: no
        /// frames are written while the screen is still.
        public var duration: Double

        public init(file: String, duration: Double) {
            self.file = file
            self.duration = duration
        }
    }

    public var scene: String
    public var display: Display
    /// Video file name in the take's directory. For a take in segments the
    /// host joins them into it before cutting outputs.
    public var video: String?
    public var segments: [Segment]?
    public var duration: Double?
    public var markers: [String: Double] = [:]
    /// Union of every frame a window was seen at while recording, by target
    /// name (`picker`, or the app as the scene wrote it).
    public var windows: [String: Rect] = [:]
    public var screenshots: [String] = []
    public var events: [Event] = []
    public var warnings: [String] = []
    public var failure: String?

    public init(scene: String, display: Display) {
        self.scene = scene
        self.display = display
    }

    public static func load(from url: URL) throws -> Manifest {
        try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url)
    }

    public func resolve(_ time: TimeRef) throws -> Double {
        let base: Double
        switch time.anchor {
        case .start:
            base = 0
        case .end:
            base = duration ?? 0
        case let .marker(name):
            guard let marker = markers[name] else {
                let known = markers.keys.sorted().joined(separator: ", ")
                throw SceneError.invalid("no marker '\(name)' (markers: \(known))")
            }
            base = marker
        }
        return max(0, min(base + time.offset, duration ?? .greatestFiniteMagnitude))
    }
}

/// A moment in a take: seconds (`2.5`), a marker (`picked`), a marker with an
/// offset (`picked+0.5`, `end-1`), or `start`/`end`.
public struct TimeRef: Decodable, Sendable, Equatable {
    public enum Anchor: Sendable, Equatable {
        case start
        case end
        case marker(String)
    }

    public var anchor: Anchor
    public var offset: Double

    public init(anchor: Anchor, offset: Double = 0) {
        self.anchor = anchor
        self.offset = offset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let seconds = try? container.decode(Double.self) {
            self.init(anchor: .start, offset: seconds)
        } else {
            self = try Self.parse(container.decode(String.self))
        }
    }

    public static func parse(_ text: String) throws -> TimeRef {
        var name = text.trimmingCharacters(in: .whitespaces)
        var offset = 0.0
        // Only a trailing number is an offset, so `intro-end` stays a marker name.
        if let sign = name.lastIndex(where: { $0 == "+" || $0 == "-" }), sign != name.startIndex,
           let value = Double(name[name.index(after: sign)...])
        {
            offset = name[sign] == "-" ? -value : value
            name = String(name[..<sign])
        }
        switch name {
        case "start": return TimeRef(anchor: .start, offset: offset)
        case "end": return TimeRef(anchor: .end, offset: offset)
        default: return TimeRef(anchor: .marker(name), offset: offset)
        }
    }
}
