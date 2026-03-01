import Foundation

struct ThemeConfig: Codable, Sendable, Equatable {
    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// VSCode variants to manage themes for.
    /// Maps display name to Application Support subdirectory.
    /// Default: Code, Cursor, Windsurf.
    var vscodeVariants: [String: String]?

    /// JetBrains IDE tags to manage themes for (nil = all detected).
    var jetbrainsIDEs: Set<String>?

    /// VSCode theme names available for selection in the picker.
    var vscodeThemes: [String]?

    /// iTerm color preset names available for selection in the picker.
    var itermPresets: [String]?

    /// Theme presets. If nil, 3 defaults are provided.
    var presets: [ThemePreset]?
}

struct ThemePreset: Codable, Sendable, Equatable {
    let name: String
    var icon: String?
    var subtitle: String?
    var appearance: String?
    var accentColor: String?
    var wallpaper: String?
    var vscodeTheme: String?
    var jetbrainsTheme: String?
    var itermPreset: String?
    var githubTheme: String?
    var keywords: [String]?
}

extension ThemeConfig {
    static let defaultPresets: [ThemePreset] = [
        ThemePreset(
            name: "Dark Focus",
            icon: "moon.stars",
            subtitle: "Dark mode with muted accent",
            appearance: "dark",
            accentColor: "Graphite",
            vscodeTheme: "Default Dark Modern",
            jetbrainsTheme: "Darcula",
            itermPreset: "Solarized Dark",
            githubTheme: "auto"
        ),
        ThemePreset(
            name: "Light Clean",
            icon: "sun.max",
            subtitle: "Light mode with blue accent",
            appearance: "light",
            accentColor: "Blue",
            vscodeTheme: "Default Light Modern",
            jetbrainsTheme: "IntelliJ Light",
            itermPreset: "Light Background",
            githubTheme: "auto"
        ),
        ThemePreset(
            name: "Warm Night",
            icon: "flame",
            subtitle: "Warm dark theme for night coding",
            appearance: "dark",
            accentColor: "Orange",
            vscodeTheme: "Monokai",
            jetbrainsTheme: "Darcula",
            itermPreset: "Tango Dark",
            githubTheme: "auto"
        ),
    ]

    static let defaultVSCodeThemes: [String] = [
        "Default Dark Modern",
        "Default Light Modern",
        "One Dark Pro",
        "Dracula",
        "Solarized Dark",
        "Solarized Light",
        "Monokai",
        "GitHub Dark",
        "GitHub Light",
        "Nord",
        "Catppuccin Mocha",
        "Catppuccin Latte",
    ]

    static let defaultGitHubThemes: [String] = [
        "Auto",
        "Light",
        "Dark",
        "Dark Dimmed",
    ]

    static let defaultITermPresets: [String] = [
        "Solarized Dark",
        "Solarized Light",
        "Tango Dark",
        "Tango Light",
        "Light Background",
        "Dark Background",
        "Pastel (Dark Background)",
        "Smoooooth",
    ]
}
