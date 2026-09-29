import Foundation

/// The classic Mac OS: System 7, Mac OS 8 and 9's Platinum, and the Hi-Tech appearance
/// from Mac OS 8.5's betas. The greys are Platinum's (#DDDDDD windows), and the syntax hues
/// are the Macintosh 16-color system palette (red DD0806, green 006412, blue 0000D4, tan
/// 90713A, …), darkened where the original is too bright for white. The highlight and
/// desktop colors are inspired by each system's desktop rather than measured from it.
extension BuiltInThemes {
    static let classicMac: [ThemeDefinition] = [system7, macOS8, macOS9, hiTech]

    /// Hues shared by the light themes, from the Macintosh 16-color palette.
    private static let macHues: [String: String] = [
        "background": "#ffffff", "foreground": "#000000", "bright_foreground": "#000000",
        "cursor": "#000000", "muted": "#808080",
        "lighter_background": "#eeeeee", "dark_background": "#dddddd", "darker_background": "#bbbbbb",
        "color0": "#000000", "color7": "#c0c0c0", "color8": "#808080", "color15": "#ffffff",
        "red": "#dd0806", "orange": "#c04a00", "brown": "#562c05", "yellow": "#8a7000",
        "green": "#006412", "cyan": "#04799f", "blue": "#0000d4", "magenta": "#a2006e",
        "bright_red": "#f0281c", "bright_yellow": "#c8a800", "bright_green": "#1fb714",
        "bright_cyan": "#02abea", "bright_blue": "#3a3af0", "bright_magenta": "#f20884",
    ]

    static let system7 = ThemeDefinition(
        name: "System 7",
        mode: .light,
        // The desktop is the average of the pebble tile, so the wallpaper reproduces it exactly.
        colors: macHues.merging([
            "accent": "#6666cc", "selection_background": "#9999ff", "selection_foreground": "#000000",
            "desktop": "#6a6aa7", "highlight": "#9999ff",
        ]) { _, new in new },
        wallpaperStyle: WallpaperStyle.pebbles.rawValue,
        icon: "desktopcomputer",
        keywords: ["system7", "system 7", "macintosh", "mac", "apple", "classic", "retro", "pebbles"]
    )

    static let macOS8 = ThemeDefinition(
        name: "Mac OS 8",
        mode: .light,
        colors: macHues.merging([
            "accent": "#4a5aa8", "selection_background": "#b3bce6", "selection_foreground": "#000000",
            "desktop": "#8c94c4", "highlight": "#b3bce6",
        ]) { _, new in new },
        wallpaperStyle: WallpaperStyle.pinstripe.rawValue,
        icon: "display",
        keywords: ["macos8", "mac os 8", "platinum", "macintosh", "mac", "apple", "classic", "retro"]
    )

    static let macOS9 = ThemeDefinition(
        name: "Mac OS 9",
        mode: .light,
        colors: macHues.merging([
            "accent": "#2f7f8a", "selection_background": "#a6d0d4", "selection_foreground": "#000000",
            "desktop": "#7fb3b8", "highlight": "#a6d0d4",
        ]) { _, new in new },
        wallpaperStyle: WallpaperStyle.macpattern.rawValue,
        icon: "apple.logo",
        keywords: ["macos9", "mac os 9", "platinum", "macintosh", "mac", "apple", "classic", "retro", "teal"]
    )

    /// The Hi-Tech appearance: "shades of black", like audio-visual equipment.
    static let hiTech = ThemeDefinition(
        name: "Mac OS Hi-Tech",
        mode: .dark,
        colors: [
            "background": "#1c1c1c", "foreground": "#d9d9d9", "bright_foreground": "#ffffff",
            "accent": "#58b8e8", "cursor": "#58b8e8", "selection_background": "#33495a",
            "selection_foreground": "#ffffff", "muted": "#7a7a7a", "desktop": "#262626",
            "lighter_background": "#2a2a2a", "dark_background": "#141414", "darker_background": "#0c0c0c",
            "color0": "#141414", "color7": "#cccccc", "color8": "#666666", "color15": "#ffffff",
            "red": "#e0574f", "orange": "#e09850", "yellow": "#d9c355", "green": "#62c26f",
            "cyan": "#58b8e8", "blue": "#5a8de0", "magenta": "#b479d8",
            "bright_red": "#f0736b", "bright_yellow": "#eedb70", "bright_green": "#7fd88a",
            "bright_cyan": "#7fcdf0", "bright_blue": "#7ba6ee", "bright_magenta": "#c99be6",
        ],
        wallpaperStyle: WallpaperStyle.pinstripe.rawValue,
        icon: "hifispeaker",
        keywords: ["hi-tech", "hitech", "macos", "mac os 8.5", "macintosh", "mac", "apple", "classic", "black"]
    )
}
