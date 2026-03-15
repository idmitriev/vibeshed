import SwiftUI

struct VibeTheme: Equatable, Sendable {
    let accent: Color
    let backgroundTint: Color?
    let selectionHighlight: Color
    let searchHighlight: Color
    let iconTint: Color?
    let shadowColor: Color?

    static let `default` = VibeTheme(
        accent: .accentColor,
        backgroundTint: nil,
        selectionHighlight: Color.accentColor.opacity(0.08),
        searchHighlight: .accentColor,
        iconTint: nil,
        shadowColor: nil
    )
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
