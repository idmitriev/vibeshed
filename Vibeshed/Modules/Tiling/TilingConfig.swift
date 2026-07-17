import Foundation

struct TilingConfig: Codable, Sendable, Equatable {
    var displays: [DisplayGridConfig]
    var defaultGrid: DisplayGridConfig?
    var padding: PaddingConfig
    var enabledActions: Set<String>?
    var autoTile: AutoTileConfig

    static let defaultValue = TilingConfig(
        displays: [],
        defaultGrid: DisplayGridConfig(
            match: nil,
            columns: [1, 1],
            rows: [1, 1],
            padding: nil
        ),
        padding: PaddingConfig(),
        enabledActions: nil,
        autoTile: AutoTileConfig()
    )
}

/// Tuning parameters for auto-tile. Whether auto-tile is actually running is *not*
/// config — it's runtime-only state toggled via `tiling/enableAutoTile` /
/// `tiling/disableAutoTile`, and always starts off on launch.
struct AutoTileConfig: Codable, Sendable, Equatable {
    /// Bundle IDs to never auto-tile (manual `tiling/attach` still works on them).
    var excludedBundleIDs: [String] = []
    /// How often (seconds) to poll for window creation/move/resize while auto-tile is enabled.
    var pollingInterval: Double = 1.0
    /// Skip windows narrower or shorter than this (points) — filters out tooltips, HUDs,
    /// and other tiny non-content windows that shouldn't be stretched into a grid cell.
    var minimumSize: Double = 100

    init(
        excludedBundleIDs: [String] = [],
        pollingInterval: Double = 1.0,
        minimumSize: Double = 100
    ) {
        self.excludedBundleIDs = excludedBundleIDs
        self.pollingInterval = pollingInterval
        self.minimumSize = minimumSize
    }

    // Custom Decodable: a missing key falls back to its default above instead of
    // throwing keyNotFound. Plain synthesized Decodable does NOT do this — a
    // property's `= default` only applies to the memberwise initializer, not to
    // decoding — so every new field here previously required updating every
    // existing config.yaml in lockstep or the whole TilingConfig would silently
    // fall back to .defaultValue (see ModuleConfigDecoder's decode-error logging).
    enum CodingKeys: String, CodingKey {
        case excludedBundleIDs, pollingInterval, minimumSize
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs) ?? []
        pollingInterval = try container.decodeIfPresent(Double.self, forKey: .pollingInterval) ?? 1.0
        minimumSize = try container.decodeIfPresent(Double.self, forKey: .minimumSize) ?? 100
    }
}

struct DisplayGridConfig: Codable, Sendable, Equatable {
    /// Matched against a screen's `NSScreen.localizedName` (e.g. "Kuycon P20", exact match),
    /// "main" (the primary display), or its 0-based positional index ("0", "1", ...).
    /// Required (non-empty) for entries in `displays`; unused/omittable for `defaultGrid`.
    var match: String?
    var columns: [Double]
    var rows: [Double]
    var padding: PaddingConfig?
}
