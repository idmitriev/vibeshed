import AppKit
import Foundation

// MARK: - Appearance (light / dark)

struct AppearanceTarget: ThemeTarget {
    let id = ThemeTargetID.appearance
    let displayName = "Appearance"
    var supportsPreview: Bool { true }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let wantsDark = request.palette.mode == .dark
        if await Self.isDark() == wantsDark { return .applied() }
        return await Self.setDark(wantsDark)
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        let wasDark = await Self.isDark()
        return { _ = await Self.setDark(wasDark) }
    }

    @MainActor
    private static func isDark() -> Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private static func setDark(_ dark: Bool) async -> ThemeTargetOutcome {
        let script = """
        tell application "System Events"
            tell appearance preferences to set dark mode to \(dark)
        end tell
        """
        do {
            try await AppleScriptRunner.run(script)
            return .applied()
        } catch {
            return .failed("allow Vibeshed to control System Events (\(error.localizedDescription))")
        }
    }
}

// MARK: - Accent + text highlight color

/// Sets the system accent to the named color nearest the palette's accent (macOS only
/// offers presets), and the text highlight color to the exact palette color ("Other").
struct AccentTarget: ThemeTarget {
    let id = ThemeTargetID.accent
    let displayName = "Accent & highlight"
    var supportsPreview: Bool { true }

    private static let keys = ["AppleAccentColor", "AppleHighlightColor", "AppleAquaColorVariant"]
    private static let notifications = ["AppleAquaColorVariantChanged", "AppleColorPreferencesChangedNotification"]

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let named = request.theme.macosAccent.flatMap(MacAccentColor.named)
            ?? MacAccentColor.nearest(to: request.palette.accent)
        let highlight = request.palette["highlight"] ?? request.palette.accent.mix(.white, 0.55)

        let values: [String: Any?] = [
            "AppleAccentColor": named.preferenceValue,
            "AppleHighlightColor": String(
                format: "%.6f %.6f %.6f Other", highlight.red, highlight.green, highlight.blue
            ),
            "AppleAquaColorVariant": named == .graphite ? 6 : 1,
        ]
        guard Self.write(values) else { return .failed("couldn't write global preferences") }
        return .applied()
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        var saved: [String: Any?] = [:]
        for key in Self.keys {
            saved.updateValue(SystemPreferences.value(key), forKey: key)
        }
        nonisolated(unsafe) let restore = saved
        return { Self.write(restore) }
    }

    @discardableResult
    private static func write(_ values: [String: Any?]) -> Bool {
        var ok = true
        for (key, value) in values {
            ok = SystemPreferences.set(value, forKey: key) && ok
        }
        SystemPreferences.postDistributed(notifications)
        return ok
    }
}

/// The accent presets macOS offers, with their `AppleAccentColor` values and hues.
enum MacAccentColor: String, CaseIterable {
    case multicolor, blue, purple, pink, red, orange, yellow, green, graphite

    var preferenceValue: Int? {
        switch self {
        case .multicolor: nil
        case .red: 0
        case .orange: 1
        case .yellow: 2
        case .green: 3
        case .blue: 4
        case .purple: 5
        case .pink: 6
        case .graphite: -1
        }
    }

    /// Approximate hue of the preset, for nearest-color mapping.
    private var hue: Double? {
        switch self {
        case .red: 358
        case .orange: 30
        case .yellow: 48
        case .green: 105
        case .blue: 211
        case .purple: 295
        case .pink: 330
        case .multicolor, .graphite: nil
        }
    }

    static func named(_ name: String) -> MacAccentColor? {
        MacAccentColor(rawValue: name.lowercased())
    }

    /// Graphite for near-greys, otherwise the preset with the closest hue.
    static func nearest(to color: ThemeColor) -> MacAccentColor {
        let hsl = color.hsl
        guard hsl.saturation > 0.18 else { return .graphite }
        return allCases
            .compactMap { preset in preset.hue.map { (preset, ThemeColor.hueDistance($0, hsl.hue)) } }
            .min { $0.1 < $1.1 }?.0 ?? .blue
    }
}

// MARK: - Pointer

/// The Accessibility pointer colors (System Settings › Accessibility › Display › Pointer):
/// fill from the accent, outline from the palette's lightest tone so it stays visible.
/// Themes can set `pointer_fill` / `pointer_outline` explicitly.
struct PointerTarget: ThemeTarget {
    let id = ThemeTargetID.pointer
    let displayName = "Pointer"
    var supportsPreview: Bool { true }

    private static let domain = "com.apple.universalaccess"
    private static let keys = ["cursorFill", "cursorOutline", "cursorIsCustomized"]

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let palette = request.palette
        let fill = palette["pointer_fill"] ?? palette.accent
        let lightest = [palette.background, palette.brightForeground].max {
            $0.relativeLuminance < $1.relativeLuminance
        } ?? .white
        let outline = palette["pointer_outline"] ?? lightest

        let values: [String: Any?] = [
            "cursorFill": Self.dictionary(fill),
            "cursorOutline": Self.dictionary(outline),
            "cursorIsCustomized": true,
        ]
        // The domain is privacy-protected: a refused write can still "succeed", so read it back.
        guard Self.write(values), Self.stored(fill) else {
            return .failed("macOS refused the pointer setting — grant Vibeshed Full Disk Access")
        }
        return .applied()
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        var saved: [String: Any?] = [:]
        for key in Self.keys {
            saved.updateValue(SystemPreferences.value(key, domain: Self.domain), forKey: key)
        }
        nonisolated(unsafe) let restore = saved
        return { Self.write(restore) }
    }

    private static func stored(_ fill: ThemeColor) -> Bool {
        guard let saved = SystemPreferences.value("cursorFill", domain: domain) as? [String: Any],
              let red = (saved["red"] as? NSNumber)?.doubleValue
        else { return false }
        return abs(red - fill.red) < 0.001
    }

    private static func dictionary(_ color: ThemeColor) -> [String: Double] {
        ["red": color.red, "green": color.green, "blue": color.blue, "alpha": 1]
    }

    @discardableResult
    private static func write(_ values: [String: Any?]) -> Bool {
        var ok = true
        for (key, value) in values {
            ok = SystemPreferences.set(value, forKey: key, domain: domain) && ok
        }
        // The change notification the Accessibility frameworks use for mouse settings.
        // There's no public API for pointer colors, so live pickup is best-effort.
        SystemPreferences.postDistributed(["UniversalAccessDomainMouseSettingsDidChangeNotification"])
        return ok
    }
}
