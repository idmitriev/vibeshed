import SwiftUI

/// Colors for Vibeshed's own UI (picker, keystroke chips). Comes from the applied
/// palette theme; without one, the system accent.
struct PickerTheme: Equatable, Sendable {
    let accent: Color
    /// Text/icon color drawn on top of `accent` (selected rows).
    var accentForeground: Color = .white
    let backgroundTint: Color?
    let selectionHighlight: Color
    let searchHighlight: Color
    let iconTint: Color?
    let shadowColor: Color?

    static let `default` = PickerTheme(
        accent: .accentColor,
        backgroundTint: nil,
        selectionHighlight: Color.accentColor.opacity(0.14),
        searchHighlight: .accentColor,
        iconTint: nil,
        shadowColor: nil
    )

    /// The theme for the palette on display (applied or live-previewed). Reading it
    /// from a view body re-renders the view when the palette changes.
    @MainActor
    static var current: PickerTheme {
        ActiveTheme.shared.displayed.map { PickerTheme(palette: $0.palette) } ?? .default
    }
}

extension PickerTheme {
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

private struct PickerThemeKey: EnvironmentKey {
    static let defaultValue: PickerTheme = .default
}

extension EnvironmentValues {
    var pickerTheme: PickerTheme {
        get { self[PickerThemeKey.self] }
        set { self[PickerThemeKey.self] = newValue }
    }
}
