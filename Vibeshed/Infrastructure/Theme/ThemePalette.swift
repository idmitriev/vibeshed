import Foundation

enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case dark
    case light
}

/// A fully resolved theme palette: every semantic key a target or template can ask for.
///
/// Key names deliberately match Omarchy's `colors.toml` (`background`, `bright_blue`,
/// `selection_background`, `color0`…`color15`, …) so an Omarchy theme's colors can be
/// pasted into Vibeshed config, and Omarchy `.tpl` templates render unchanged. Any
/// palette defined with only a handful of keys is completed by `resolve(_:mode:)`,
/// which ports Omarchy's alias/derivation cascade.
struct ThemePalette: Sendable, Equatable, Codable {
    let mode: ThemeMode
    /// Every resolved key → color, including aliases (`color0`…`color15`, `purple`, `bg`, …)
    /// and any custom keys the theme defined (e.g. `pointer_fill`).
    let colors: [String: ThemeColor]

    subscript(key: String) -> ThemeColor? {
        colors[key]
    }

    // MARK: - Semantic accessors (always present after resolution)

    var background: ThemeColor { value("background") }
    var darkBackground: ThemeColor { value("dark_background") }
    var darkerBackground: ThemeColor { value("darker_background") }
    var lighterBackground: ThemeColor { value("lighter_background") }
    var foreground: ThemeColor { value("foreground") }
    var darkForeground: ThemeColor { value("dark_foreground") }
    var brightForeground: ThemeColor { value("bright_foreground") }
    var accent: ThemeColor { value("accent") }
    var cursor: ThemeColor { value("cursor") }
    var muted: ThemeColor { value("muted") }
    var selectionBackground: ThemeColor { value("selection_background") }
    var selectionForeground: ThemeColor { value("selection_foreground") }
    var red: ThemeColor { value("red") }
    var orange: ThemeColor { value("orange") }
    var yellow: ThemeColor { value("yellow") }
    var green: ThemeColor { value("green") }
    var cyan: ThemeColor { value("cyan") }
    var blue: ThemeColor { value("blue") }
    var magenta: ThemeColor { value("magenta") }

    /// The 16 terminal colors, `color0`…`color15`.
    var ansi: [ThemeColor] {
        (0 ..< 16).map { value("color\($0)") }
    }

    /// The handful of colors that identify a theme at a glance — used for list swatches.
    var signature: [ThemeColor] {
        [background, foreground, accent, red, yellow, green, cyan, blue, magenta]
    }

    private func value(_ key: String) -> ThemeColor {
        colors[key] ?? (mode == .dark ? .black : .white)
    }

    /// Placeholder values for templates: every color key as `#rrggbb`, plus `mode`
    /// and its Omarchy alias `theme_type`.
    var templateVariables: [String: String] {
        var variables = colors.mapValues(\.hex)
        variables["mode"] = mode.rawValue
        variables["theme_type"] = mode.rawValue
        return variables
    }
}

// MARK: - Resolution

enum ThemePaletteError: LocalizedError, Equatable {
    case invalidColor(key: String, value: String)
    case invalidMode(String)
    case missingKeys([String])

    var errorDescription: String? {
        switch self {
        case let .invalidColor(key, value):
            "'\(key)' is not a hex color: '\(value)'"
        case let .invalidMode(value):
            "mode must be 'dark' or 'light', got '\(value)'"
        case let .missingKeys(keys):
            "missing colors: \(keys.joined(separator: ", "))"
        }
    }
}

extension ThemePalette {
    /// Keys that aren't colors and must not be parsed as hex.
    static let nonColorKeys: Set<String> = ["mode", "theme_type", "name"]

    /// Semantic hue keys: every palette needs these (directly or via `color1`…`color6`).
    static let requiredHueKeys = ["red", "green", "yellow", "blue", "magenta", "cyan"]

    /// Resolves a raw `key → "#hex"` map into a complete palette.
    ///
    /// Mirrors `omarchy-theme-color`'s cascade — legacy short names (`bg`, `fg`, …),
    /// ANSI `colorN` ↔ semantic names, derived shades (`dark_background` = 25% toward
    /// black, `bright_red` = 20% toward white, …) — with two deliberate differences:
    /// an explicitly given `colorN` is kept rather than overwritten by its semantic
    /// twin, and `lighter_background`/`selection_background` fall back to blends
    /// instead of reusing `background`/`color8`, which reads better in UI surfaces.
    static func resolve(_ raw: [String: String], mode explicitMode: ThemeMode? = nil) throws -> ThemePalette {
        var colors: [String: ThemeColor] = [:]
        for (key, value) in raw where !nonColorKeys.contains(key) {
            guard let color = ThemeColor(hex: value) else {
                throw ThemePaletteError.invalidColor(key: key, value: value)
            }
            colors[key] = color
        }

        applyLegacyAliases(&colors)
        guard colors["background"] != nil, colors["foreground"] != nil else {
            throw ThemePaletteError.missingKeys(["background", "foreground"].filter { colors[$0] == nil })
        }
        let missingHues = requiredHueKeys.filter { colors[$0] == nil }
        guard missingHues.isEmpty else { throw ThemePaletteError.missingKeys(missingHues) }

        let mode: ThemeMode
        if let explicitMode {
            mode = explicitMode
        } else if let rawMode = raw["mode"] ?? raw["theme_type"] {
            guard let parsed = ThemeMode(rawValue: rawMode.lowercased()) else {
                throw ThemePaletteError.invalidMode(rawMode)
            }
            mode = parsed
        } else {
            mode = (colors["background"]?.isLight ?? false) ? .light : .dark
        }

        deriveShades(&colors, mode: mode)
        applyANSIAliases(&colors)
        return ThemePalette(mode: mode, colors: colors)
    }

    /// Fills semantic names from legacy short names and from ANSI `colorN` slots.
    private static func applyLegacyAliases(_ colors: inout [String: ThemeColor]) {
        let shortNames = [
            "background": "bg", "dark_background": "dark_bg", "darker_background": "darker_bg",
            "lighter_background": "lighter_bg", "foreground": "fg", "dark_foreground": "dark_fg",
            "light_foreground": "light_fg", "bright_foreground": "bright_fg",
        ]
        for (key, short) in shortNames where colors[key] == nil {
            colors[key] = colors[short]
        }
        let ansiSources = [
            "background": "color0", "red": "color1", "green": "color2", "yellow": "color3",
            "blue": "color4", "magenta": "color5", "cyan": "color6", "foreground": "color7",
            "bright_red": "color9", "bright_green": "color10", "bright_yellow": "color11",
            "bright_blue": "color12", "bright_magenta": "color13", "bright_cyan": "color14",
        ]
        for (key, source) in ansiSources where colors[key] == nil {
            colors[key] = colors[source]
        }
        colors["magenta"] = colors["magenta"] ?? colors["purple"]
        colors["bright_magenta"] = colors["bright_magenta"] ?? colors["bright_purple"]
    }

    /// Derives every shade a theme didn't define. Requires background, foreground and
    /// the six base hues to be present.
    private static func deriveShades(_ colors: inout [String: ThemeColor], mode: ThemeMode) {
        func fill(_ key: String, _ value: ThemeColor?) {
            if colors[key] == nil, let value { colors[key] = value }
        }
        let background = colors["background"] ?? .black
        let foreground = colors["foreground"] ?? .white

        fill("accent", colors["blue"])
        fill("light_foreground", colors["color7"] ?? foreground)
        fill("bright_foreground", colors["color15"] ?? foreground)
        fill("cursor", colors["bright_foreground"])
        fill("lighter_background", background.mix(foreground, 0.08))
        fill("dark_foreground", colors["color8"] ?? foreground.mix(background, 0.45))
        fill("muted", colors["color8"] ?? colors["dark_foreground"])
        fill("selection_background", colors["selection"] ?? background.mix(colors["accent"] ?? foreground, 0.3))
        fill("selection", colors["selection_background"])
        fill("selection_foreground", colors["bright_foreground"])
        fill("orange", colors["yellow"])
        fill("brown", colors["orange"]?.mix(.black, 0.5))
        // Omarchy's 25%/50% toward black; light themes get gentle steps instead, since
        // these become sidebars and panels (a quarter-black sidebar on white is grey mud).
        let (dark, darker) = mode == .dark ? (0.25, 0.5) : (0.04, 0.08)
        fill("dark_background", background.mix(.black, dark))
        fill("darker_background", background.mix(.black, darker))
        for hue in requiredHueKeys {
            fill("bright_\(hue)", colors[hue]?.mix(.white, 0.2))
        }
        fill("purple", colors["magenta"])
        fill("bright_purple", colors["bright_magenta"])
    }

    /// Fills `colorN` (and legacy short names) from semantic names for templates that
    /// still reference them. Explicit `colorN` values are kept.
    private static func applyANSIAliases(_ colors: inout [String: ThemeColor]) {
        let ansi = [
            "background", "red", "green", "yellow", "blue", "magenta", "cyan", "foreground",
            "muted", "bright_red", "bright_green", "bright_yellow", "bright_blue", "bright_magenta",
            "bright_cyan", "bright_foreground",
        ]
        for (index, key) in ansi.enumerated() where colors["color\(index)"] == nil {
            colors["color\(index)"] = colors[key]
        }
        let shortNames = [
            "bg": "background", "fg": "foreground", "dark_bg": "dark_background",
            "darker_bg": "darker_background", "lighter_bg": "lighter_background",
            "dark_fg": "dark_foreground", "light_fg": "light_foreground", "bright_fg": "bright_foreground",
        ]
        for (short, key) in shortNames where colors[short] == nil {
            colors[short] = colors[key]
        }
    }
}
