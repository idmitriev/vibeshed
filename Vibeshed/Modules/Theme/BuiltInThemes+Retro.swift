import Foundation

/// Classic desktop operating systems. UI colors come from the systems themselves:
/// BeOS from Haiku's `_kDefaultColors` (which keeps BeOS R5's defaults), OS/2 Warp 4 from
/// its window scheme (grey #CFCFCF windows, blue title bars) and Presentation Manager's
/// 16-color table, OS/2 text mode from the VGA text palette, NeXTSTEP from OpenStep's
/// grays (NSLightGray 2/3, NSDarkGray 1/3) and its standard NSColors. Syntax hues are
/// those palettes' own colors, darkened where the pure ones are unreadable on white.
extension BuiltInThemes {
    static let retro: [ThemeDefinition] = [beos, os2Warp, os2TextMode, nextstep]

    static let beos = ThemeDefinition(
        name: "BeOS",
        mode: .light,
        colors: [
            "background": "#ffffff", "foreground": "#000000", "bright_foreground": "#000000",
            "accent": "#ffcb00", "cursor": "#000000", "selection_background": "#bebebe",
            "selection_foreground": "#000000", "muted": "#6e6e6e", "desktop": "#336698",
            "lighter_background": "#e8e8e8", "dark_background": "#d8d8d8", "darker_background": "#acacac",
            "pointer_outline": "#000000", "highlight": "#6698cb",
            "color0": "#000000", "color7": "#d8d8d8", "color8": "#6e6e6e", "color15": "#ffffff",
            "red": "#cc2f24", "orange": "#d9661a", "yellow": "#b58a00", "green": "#1f8a2c",
            "cyan": "#1f7a8c", "blue": "#336698", "magenta": "#91709b",
            "bright_red": "#ff4136", "bright_yellow": "#ffcb00", "bright_green": "#2ecc40",
            "bright_cyan": "#3fb5c6", "bright_blue": "#6698cb", "bright_magenta": "#b48cc0",
        ],
        wallpaperStyle: WallpaperStyle.leaves.rawValue,
        icon: "macwindow",
        keywords: ["beos", "haiku", "be", "retro", "yellow"]
    )

    static let os2Warp = ThemeDefinition(
        name: "OS/2 Warp",
        mode: .light,
        colors: [
            "background": "#ffffff", "foreground": "#000000", "bright_foreground": "#000000",
            "accent": "#0202ca", "cursor": "#000000", "selection_background": "#828282",
            "selection_foreground": "#ffffff", "muted": "#686868", "desktop": "#008080",
            "lighter_background": "#e7e7e7", "dark_background": "#cfcfcf", "darker_background": "#878787",
            "color0": "#000000", "color1": "#800000", "color2": "#008000", "color3": "#808000",
            "color4": "#000080", "color5": "#800080", "color6": "#008080", "color7": "#cccccc",
            "color8": "#808080", "color9": "#ff0000", "color10": "#00ff00", "color11": "#ffff00",
            "color12": "#0000ff", "color13": "#ff00ff", "color14": "#00ffff", "color15": "#ffffff",
            "red": "#800000", "orange": "#b35900", "yellow": "#808000", "green": "#008000",
            "cyan": "#008080", "blue": "#000080", "magenta": "#800080",
            "bright_red": "#ff0000", "bright_yellow": "#808000", "bright_green": "#008000",
            "bright_cyan": "#008080", "bright_blue": "#0000ff", "bright_magenta": "#c000c0",
        ],
        wallpaperStyle: WallpaperStyle.warp.rawValue,
        icon: "hurricane",
        keywords: ["os2", "warp", "ibm", "retro", "presentation manager"]
    )

    static let os2TextMode = ThemeDefinition(
        name: "OS/2 Text Mode",
        mode: .dark,
        colors: [
            "background": "#0000aa", "foreground": "#ffffff", "bright_foreground": "#ffffff",
            "accent": "#ffff55", "cursor": "#aaaaaa", "selection_background": "#00aaaa",
            "selection_foreground": "#000000", "muted": "#aaaaaa", "desktop": "#0000aa",
            "lighter_background": "#0000c4", "dark_background": "#00008a", "darker_background": "#000066",
            "color0": "#000000", "color1": "#aa0000", "color2": "#00aa00", "color3": "#aa5500",
            "color4": "#0000aa", "color5": "#aa00aa", "color6": "#00aaaa", "color7": "#aaaaaa",
            "color8": "#555555", "color9": "#ff5555", "color10": "#55ff55", "color11": "#ffff55",
            "color12": "#5555ff", "color13": "#ff55ff", "color14": "#55ffff", "color15": "#ffffff",
            "red": "#ff5555", "yellow": "#ffff55", "green": "#55ff55", "cyan": "#00aaaa",
            "blue": "#55ffff", "magenta": "#ff55ff",
            "bright_red": "#ff5555", "bright_yellow": "#ffff55", "bright_green": "#55ff55",
            "bright_cyan": "#55ffff", "bright_blue": "#55ffff", "bright_magenta": "#ff55ff",
        ],
        wallpaperStyle: WallpaperStyle.textmode.rawValue,
        icon: "terminal",
        keywords: ["os2", "text", "vga", "dos", "retro", "blue"]
    )

    static let nextstep = ThemeDefinition(
        name: "NeXTSTEP",
        mode: .light,
        colors: [
            "background": "#ffffff", "foreground": "#000000", "bright_foreground": "#000000",
            "accent": "#000000", "cursor": "#000000", "selection_background": "#aaaaaa",
            "selection_foreground": "#000000", "muted": "#555555", "desktop": "#555555",
            "lighter_background": "#d5d5d5", "dark_background": "#aaaaaa", "darker_background": "#555555",
            "color0": "#000000", "color7": "#aaaaaa", "color8": "#555555", "color15": "#ffffff",
            "color9": "#ff0000", "color10": "#00ff00", "color11": "#ffff00", "color12": "#0000ff",
            "color13": "#ff00ff", "color14": "#00ffff",
            "red": "#990000", "orange": "#cc6600", "brown": "#996633", "yellow": "#806f00",
            "green": "#008000", "cyan": "#008080", "blue": "#000099", "magenta": "#990099",
            "bright_red": "#ff0000", "bright_yellow": "#806f00", "bright_green": "#00a000",
            "bright_cyan": "#00a3a3", "bright_blue": "#0000ff", "bright_magenta": "#b300b3",
        ],
        wallpaperStyle: WallpaperStyle.polyhedra.rawValue,
        icon: "cube",
        keywords: ["nextstep", "next", "openstep", "jobs", "retro", "gray"]
    )
}
