import Foundation

extension AppConfig {
    /// `appearance.overlay`: a backdrop over the screen behind the open picker — blur,
    /// tint, vignette and grain — animated in and out with it.
    ///
    /// On when present, like a module section: `overlay:` alone (or `overlay: true`)
    /// uses these defaults. Every field is optional, and a malformed one falls back to
    /// its default on its own (logged) instead of discarding the whole section.
    struct OverlayConfig: Codable, Sendable, Equatable {
        var enabled = true
        /// Blur radius in points; 0 leaves the screen sharp.
        var blur = 24.0
        /// Saturation of what shows through the blur: 0 greyscale, 1 unchanged, 2 vivid.
        var saturation = 1.4
        /// A system material's own tint over the blur, under `color`.
        var material: OverlayMaterial = .none
        var color: OverlayColor = .theme
        /// How strongly `color` covers the screen, 0–1.
        var opacity = 0.25
        /// Extra `color` toward the screen edges, 0–1.
        var vignette = 0.3
        /// Film grain, 0–1.
        var grain = 0.0
        /// Cover every display, not only the picker's.
        var allScreens = false
        /// Pass clicks to the app underneath (which also closes the picker). Off, a
        /// click on the overlay only closes the picker.
        var clickThrough = false
        var showAnimation: OverlayAnimation = .fade
        /// Seconds.
        var showDuration = 0.3
        var hideAnimation: OverlayAnimation = .fade
        /// Seconds.
        var hideDuration = 0.2

        init() {}

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Self()
            enabled = container.lenient(.enabled, default: defaults.enabled)
            blur = container.lenient(.blur, default: defaults.blur, in: 0 ... 100)
            saturation = container.lenient(.saturation, default: defaults.saturation, in: 0 ... 3)
            material = container.lenient(.material, default: defaults.material)
            color = container.lenient(.color, default: defaults.color)
            opacity = container.lenient(.opacity, default: defaults.opacity, in: 0 ... 1)
            vignette = container.lenient(.vignette, default: defaults.vignette, in: 0 ... 1)
            grain = container.lenient(.grain, default: defaults.grain, in: 0 ... 1)
            allScreens = container.lenient(.allScreens, default: defaults.allScreens)
            clickThrough = container.lenient(.clickThrough, default: defaults.clickThrough)
            showAnimation = container.lenient(.showAnimation, default: defaults.showAnimation)
            showDuration = container.lenient(.showDuration, default: defaults.showDuration, in: 0 ... 2)
            hideAnimation = container.lenient(.hideAnimation, default: defaults.hideAnimation)
            hideDuration = container.lenient(.hideDuration, default: defaults.hideDuration, in: 0 ... 2)
        }
    }
}

/// How the overlay comes and goes (`showAnimation` / `hideAnimation`).
enum OverlayAnimation: String, Codable, Sendable, CaseIterable {
    /// Cross-fade.
    case fade
    /// Focus pull: the blur radius ramps up on show and back down on hide.
    case blur
    /// A soft circle opening out from the picker, closing back into it on hide.
    case iris
    case none

    init(from decoder: Decoder) throws {
        self = try decodeConfigEnum(from: decoder)
    }
}

/// A system material whose own tint layers show over the blur (`material`).
enum OverlayMaterial: String, Codable, Sendable, CaseIterable {
    case none
    case hud
    case fullScreen
    case popover
    case menu
    case sidebar
    case underWindow

    init(from decoder: Decoder) throws {
        self = try decodeConfigEnum(from: decoder)
    }
}

/// `color`: a fixed `#rrggbb`, or one that follows the active theme.
enum OverlayColor: Codable, Sendable, Equatable {
    /// The palette theme's darkest background; without a palette theme, black in Dark
    /// Mode and white in Light Mode.
    case theme
    /// The picker's accent color.
    case accent
    case fixed(ThemeColor)

    init?(_ string: String) {
        switch string.trimmingCharacters(in: .whitespaces).lowercased() {
        case "theme":
            self = .theme
        case "accent":
            self = .accent
        default:
            guard let color = ThemeColor(hex: string) else { return nil }
            self = .fixed(color)
        }
    }

    var configValue: String {
        switch self {
        case .theme: "theme"
        case .accent: "accent"
        case let .fixed(color): color.hex
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = Self(string) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "'\(string)' is not #rrggbb, theme or accent"
            )
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(configValue)
    }
}

/// Decodes a string enum case-insensitively (`fullscreen` finds `fullScreen`), listing
/// the valid names when nothing matches.
private func decodeConfigEnum<T: RawRepresentable & CaseIterable>(from decoder: Decoder) throws -> T
    where T.RawValue == String
{
    let container = try decoder.singleValueContainer()
    let name = try container.decode(String.self)
    guard let match = T.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) else {
        let names = T.allCases.map(\.rawValue).joined(separator: ", ")
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(name)' is not one of \(names)")
    }
    return match
}

private extension KeyedDecodingContainer {
    /// Decodes an optional field; a malformed value is logged and replaced by `fallback`
    /// so one typo doesn't discard the rest of the section.
    func lenient<T: Decodable>(_ key: Key, default fallback: T) -> T {
        do {
            return try decodeIfPresent(T.self, forKey: key) ?? fallback
        } catch {
            let reason = switch error as? DecodingError {
            case let .dataCorrupted(context), let .typeMismatch(_, context), let .valueNotFound(_, context):
                context.debugDescription
            default:
                error.localizedDescription
            }
            let message = "Ignoring invalid 'appearance.overlay.\(key.stringValue)', using the default: \(reason)"
            Log.config.error("\(message, privacy: .public)")
            return fallback
        }
    }

    /// `lenient`, clamped into `range`.
    func lenient(_ key: Key, default fallback: Double, in range: ClosedRange<Double>) -> Double {
        min(max(lenient(key, default: fallback), range.lowerBound), range.upperBound)
    }
}
