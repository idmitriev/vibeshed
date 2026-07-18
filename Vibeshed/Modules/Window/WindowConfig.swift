import Foundation

struct WindowConfig: Codable, Sendable, Equatable {
    var horizontalStops: [SizeStop]
    var verticalStops: [SizeStop]
    /// Per-display stop overrides, matched by `DisplayStopsConfig.match`. A display with no
    /// matching entry (or an entry that leaves a dimension nil) falls back to the top-level
    /// `horizontalStops`/`verticalStops` above.
    var displays: [DisplayStopsConfig]
    var padding: PaddingConfig
    var includeMinimized: Bool
    var enlargeShrinkStep: SizeStop

    static let defaultValue = WindowConfig(
        horizontalStops: [
            SizeStop(value: 50, unit: .percent),
            SizeStop(value: 100, unit: .percent),
        ],
        verticalStops: [
            SizeStop(value: 50, unit: .percent),
            SizeStop(value: 100, unit: .percent),
        ],
        displays: [],
        padding: PaddingConfig(),
        includeMinimized: false,
        enlargeShrinkStep: SizeStop(value: 10, unit: .percent)
    )

    init(
        horizontalStops: [SizeStop],
        verticalStops: [SizeStop],
        displays: [DisplayStopsConfig] = [],
        padding: PaddingConfig,
        includeMinimized: Bool,
        enlargeShrinkStep: SizeStop
    ) {
        self.horizontalStops = horizontalStops
        self.verticalStops = verticalStops
        self.displays = displays
        self.padding = padding
        self.includeMinimized = includeMinimized
        self.enlargeShrinkStep = enlargeShrinkStep
    }

    // `displays` is decoded with decodeIfPresent so existing config.yaml files without it
    // don't fail to decode (see the Tiling module's AutoTileConfig for why: a Swift
    // property default doesn't make synthesized Decodable treat a missing key as optional).
    enum CodingKeys: String, CodingKey {
        case horizontalStops, verticalStops, displays, padding, includeMinimized, enlargeShrinkStep
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        horizontalStops = try container.decode([SizeStop].self, forKey: .horizontalStops)
        verticalStops = try container.decode([SizeStop].self, forKey: .verticalStops)
        displays = try container.decodeIfPresent([DisplayStopsConfig].self, forKey: .displays) ?? []
        padding = try container.decode(PaddingConfig.self, forKey: .padding)
        includeMinimized = try container.decode(Bool.self, forKey: .includeMinimized)
        enlargeShrinkStep = try container.decode(SizeStop.self, forKey: .enlargeShrinkStep)
    }
}

struct DisplayStopsConfig: Codable, Sendable, Equatable {
    /// Matched against a screen's `NSScreen.localizedName` (exact match), "main" (the
    /// primary display), or its 0-based positional index ("0", "1", ...).
    var match: String
    /// nil inherits the top-level `horizontalStops` for this display.
    var horizontalStops: [SizeStop]?
    /// nil inherits the top-level `verticalStops` for this display.
    var verticalStops: [SizeStop]?
}

struct SizeStop: Codable, Sendable, Equatable {
    let value: Double
    let unit: SizeUnit
}

enum SizeUnit: String, Codable, Sendable, Equatable {
    case percent
    case pixels
}

struct PaddingConfig: Codable, Sendable, Equatable {
    var top: Double = 0
    var bottom: Double = 0
    var left: Double = 0
    var right: Double = 0
    var gap: Double = 0
}
