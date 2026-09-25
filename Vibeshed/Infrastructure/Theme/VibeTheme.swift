import SwiftUI

struct VibeTheme: Equatable, Sendable {
    let accent: Color
    /// Text/icon color drawn on top of `accent` (selected rows).
    var accentForeground: Color = .white
    let backgroundTint: Color?
    let selectionHighlight: Color
    let searchHighlight: Color
    let iconTint: Color?
    let shadowColor: Color?

    static let `default` = VibeTheme(
        accent: .accentColor,
        backgroundTint: nil,
        selectionHighlight: Color.accentColor.opacity(0.14),
        searchHighlight: .accentColor,
        iconTint: nil,
        shadowColor: nil
    )
}

extension VibeTheme {
    /// Picker styling derived from an applied theme palette, so the launcher matches
    /// the rest of the desktop.
    init(palette: ThemePalette) {
        self.init(
            accent: palette.accent.color,
            accentForeground: palette.accent.contrastingText.color,
            backgroundTint: palette.background.color.opacity(0.45),
            selectionHighlight: palette.accent.color.opacity(0.18),
            searchHighlight: palette.accent.color,
            iconTint: palette.accent.color.opacity(0.85),
            shadowColor: palette.darkerBackground.color.opacity(0.45)
        )
    }
}

private struct VibeThemeKey: EnvironmentKey {
    static let defaultValue: VibeTheme = .default
}

extension EnvironmentValues {
    var vibeTheme: VibeTheme {
        get { self[VibeThemeKey.self] }
        set { self[VibeThemeKey.self] = newValue }
    }
}
