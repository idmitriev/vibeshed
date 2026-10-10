import Foundation

struct WindowConfig: Codable, Sendable, Equatable {
    var horizontalStops: [SizeStop]
    var verticalStops: [SizeStop]
    /// Per-display stop overrides, matched by `DisplayStopsConfig.match`. A display with no
    /// matching entry (or an entry that leaves a dimension nil) falls back to the top-level
    /// `horizontalStops`/`verticalStops` above.
    var displays: [DisplayStopsConfig]
    var padding: PaddingConfig
    /// Whether `window/focusWindow` also offers minimized windows.
    var includeMinimized: Bool
    var enlargeShrinkStep: SizeStop
    /// Look of the focus border and which windows get one; nil = defaults. Whether the
    /// border is drawn at all is runtime-only state toggled via `window/toggleFocusBorder`.
    var focusBorder: FocusBorderConfig?

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
        includeMinimized: true,
        enlargeShrinkStep: SizeStop(value: 10, unit: .percent)
    )

    init(
        horizontalStops: [SizeStop],
        verticalStops: [SizeStop],
        displays: [DisplayStopsConfig] = [],
        padding: PaddingConfig,
        includeMinimized: Bool,
        enlargeShrinkStep: SizeStop,
        focusBorder: FocusBorderConfig? = nil
    ) {
        self.horizontalStops = horizontalStops
        self.verticalStops = verticalStops
        self.displays = displays
        self.padding = padding
        self.includeMinimized = includeMinimized
        self.enlargeShrinkStep = enlargeShrinkStep
        self.focusBorder = focusBorder
    }

    // Every key is optional and a missing one takes its value from `defaultValue`, so a
    // section sets only what it changes (`padding:` alone, say). A Swift property default
    // doesn't make synthesized Decodable treat a missing key as optional; see the Tiling
    // module's AutoTileConfig.
    enum CodingKeys: String, CodingKey {
        case horizontalStops, verticalStops, displays, padding, includeMinimized, enlargeShrinkStep, focusBorder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultValue
        horizontalStops = try container.decodeIfPresent([SizeStop].self, forKey: .horizontalStops)
            ?? defaults.horizontalStops
        verticalStops = try container.decodeIfPresent([SizeStop].self, forKey: .verticalStops)
            ?? defaults.verticalStops
        displays = try container.decodeIfPresent([DisplayStopsConfig].self, forKey: .displays) ?? []
        padding = try container.decodeIfPresent(PaddingConfig.self, forKey: .padding) ?? defaults.padding
        includeMinimized = try container.decodeIfPresent(Bool.self, forKey: .includeMinimized)
            ?? defaults.includeMinimized
        enlargeShrinkStep = try container.decodeIfPresent(SizeStop.self, forKey: .enlargeShrinkStep)
            ?? defaults.enlargeShrinkStep
        focusBorder = try container.decodeIfPresent(FocusBorderConfig.self, forKey: .focusBorder)
    }
}

/// The border is always drawn in the active theme's accent (the system accent when no
/// theme is applied), so it has no color setting of its own.
struct FocusBorderConfig: Codable, Sendable, Equatable {
    /// Corner radius of standard macOS windows: what the window server reports for every
    /// titled window on macOS 27 (toolbar or not, AppKit or Electron).
    static let macOSWindowCornerRadius = 16.0

    var width: Double = 3.0
    /// Corner radius (points) of the outlined window's corners. The ring is drawn
    /// concentric to them, so its outer edge is `cornerRadius + width`. 0 = sharp corners.
    var cornerRadius: Double = Self.macOSWindowCornerRadius
    /// Only windows at least this many points wide *and* tall get a border — keeps it off
    /// dialogs, popovers, and other small utility windows.
    var minimumSize: Double = 200
    /// Seconds between fallback checks of the focused window. Focus changes, moves, and
    /// resizes are picked up from notifications as they happen; the poll catches what
    /// nothing announces (Mission Control, a closed last window, apps without AX
    /// notifications).
    var pollingInterval: Double = 0.15

    init(
        width: Double = 3.0,
        cornerRadius: Double = Self.macOSWindowCornerRadius,
        minimumSize: Double = 200,
        pollingInterval: Double = 0.15
    ) {
        self.width = width
        self.cornerRadius = cornerRadius
        self.minimumSize = minimumSize
        self.pollingInterval = pollingInterval
    }

    enum CodingKeys: String, CodingKey {
        case width, cornerRadius, minimumSize, pollingInterval
    }

    /// A missing key falls back to its default above instead of throwing keyNotFound and
    /// discarding the whole WindowConfig. A leftover `color` key from older configs is
    /// simply ignored.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 3.0
        cornerRadius = try container.decodeIfPresent(Double.self, forKey: .cornerRadius)
            ?? Self.macOSWindowCornerRadius
        minimumSize = try container.decodeIfPresent(Double.self, forKey: .minimumSize) ?? 200
        pollingInterval = try container.decodeIfPresent(Double.self, forKey: .pollingInterval) ?? 0.15
    }

    /// Problems with these values, for `WindowModule.validate`.
    var validationErrors: [String] {
        var errors: [String] = []
        if width <= 0 {
            errors.append("focusBorder.width must be positive")
        }
        if cornerRadius < 0 {
            errors.append("focusBorder.cornerRadius must be non-negative")
        }
        if minimumSize < 0 {
            errors.append("focusBorder.minimumSize must be non-negative")
        }
        if pollingInterval <= 0 {
            errors.append("focusBorder.pollingInterval must be positive")
        }
        return errors
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

extension PaddingConfig {
    /// A missing side is 0, so `padding: { gap: 4 }` works.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        top = try container.decodeIfPresent(Double.self, forKey: .top) ?? 0
        bottom = try container.decodeIfPresent(Double.self, forKey: .bottom) ?? 0
        left = try container.decodeIfPresent(Double.self, forKey: .left) ?? 0
        right = try container.decodeIfPresent(Double.self, forKey: .right) ?? 0
        gap = try container.decodeIfPresent(Double.self, forKey: .gap) ?? 0
    }
}
