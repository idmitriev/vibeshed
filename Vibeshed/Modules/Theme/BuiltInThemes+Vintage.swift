import Foundation

/// Windows 95 and XP, the Amiga's Workbench and QNX's Photon microGUI. UI colors are the
/// systems' own: Windows 95's 3D greys (#C0C0C0), navy selection and teal desktop, with the
/// 16-color VGA palette; XP's Luna face (#ECE9D8), #316AC5 selection and #3A6EA5 desktop;
/// Workbench 1.3's four colors (#0055AA, #000022, #FFFFFF, #FF8800) and 2.0–3.1's (#AAAAAA,
/// black, white, #6688BB), every Amiga hue kept to its 12-bit palette; Photon's #D8D8D8
/// widgets, #5C8BDF / #B1C1D9 title bars (its `wm.cfg` defaults) and the #7979A7 desktop of
/// the QNX 6.2 demo CD. Syntax hues are in each system's spirit, darkened for white paper.
extension BuiltInThemes {
    static let vintage: [ThemeDefinition] = [windows95, windowsXP, workbench13, workbench31, qnxPhoton]

    static let windows95 = ThemeDefinition(
        name: "Windows 95",
        mode: .light,
        colors: [
            "background": "#ffffff", "foreground": "#000000", "bright_foreground": "#000000",
            "accent": "#000080", "cursor": "#000000", "selection_background": "#000080",
            "selection_foreground": "#ffffff", "muted": "#808080", "desktop": "#008080", "sky": "#4a7fd4",
            // Sky blue, one of the four colors Windows reserved in its 256-color palette.
            "highlight": "#a6caf0",
            "lighter_background": "#dfdfdf", "dark_background": "#c0c0c0", "darker_background": "#808080",
            "color0": "#000000", "color1": "#800000", "color2": "#008000", "color3": "#808000",
            "color4": "#000080", "color5": "#800080", "color6": "#008080", "color7": "#c0c0c0",
            "color8": "#808080", "color9": "#ff0000", "color10": "#00ff00", "color11": "#ffff00",
            "color12": "#0000ff", "color13": "#ff00ff", "color14": "#00ffff", "color15": "#ffffff",
            "red": "#800000", "orange": "#a65200", "yellow": "#808000", "green": "#008000",
            "cyan": "#008080", "blue": "#000080", "magenta": "#800080",
            "bright_red": "#ff0000", "bright_yellow": "#808000", "bright_green": "#008000",
            "bright_cyan": "#008080", "bright_blue": "#0000ff", "bright_magenta": "#c000c0",
        ],
        wallpaperStyle: WallpaperStyle.clouds.rawValue,
        icon: "window.casement",
        keywords: ["windows", "win95", "windows 95", "microsoft", "chicago", "teal", "clouds", "retro"]
    )

    static let windowsXP = ThemeDefinition(
        name: "Windows XP",
        mode: .light,
        colors: [
            "background": "#ffffff", "foreground": "#000000", "bright_foreground": "#000000",
            "accent": "#0054e3", "cursor": "#000000", "selection_background": "#316ac5",
            "selection_foreground": "#ffffff", "muted": "#8a8778", "desktop": "#3a6ea5", "sky": "#3f86e3",
            "highlight": "#c1d2ee",
            "lighter_background": "#f5f4ea", "dark_background": "#ece9d8", "darker_background": "#aca899",
            "color0": "#000000", "color7": "#ece9d8", "color8": "#aca899", "color15": "#ffffff",
            "red": "#c42b1c", "orange": "#c86400", "brown": "#7a4a1d", "yellow": "#957700",
            "green": "#2e8b2e", "cyan": "#0a7d8c", "blue": "#0054e3", "magenta": "#9b3fa6",
            "bright_red": "#e0493a", "bright_yellow": "#b89400", "bright_green": "#3fae3f",
            "bright_cyan": "#199fb3", "bright_blue": "#3d8ef0", "bright_magenta": "#b85cc4",
        ],
        wallpaperStyle: WallpaperStyle.azul.rawValue,
        icon: "light.ribbon",
        keywords: ["windows", "xp", "windows xp", "luna", "microsoft", "azul", "retro"]
    )

    /// Workbench 1.3's blue screen, orange highlights, white text and near-black.
    static let workbench13 = ThemeDefinition(
        name: "Amiga Workbench 1.3",
        mode: .dark,
        colors: [
            "background": "#0055aa", "foreground": "#ffffff", "bright_foreground": "#ffffff",
            "accent": "#ff8800", "cursor": "#ff8800", "selection_background": "#ff8800",
            "selection_foreground": "#000022", "muted": "#88aadd", "desktop": "#0055aa", "highlight": "#ffaa55",
            "lighter_background": "#1166bb", "dark_background": "#004499", "darker_background": "#003377",
            "color0": "#000022", "color7": "#aaaaaa", "color8": "#6688bb", "color15": "#ffffff",
            "red": "#ff5544", "orange": "#ff8800", "yellow": "#ffdd44", "green": "#66ee66",
            "cyan": "#66ddff", "blue": "#aaccff", "magenta": "#ff88ff",
            "bright_red": "#ff9988", "bright_yellow": "#ffee88", "bright_green": "#99ff99",
            "bright_cyan": "#99eeff", "bright_blue": "#ccddff", "bright_magenta": "#ffaaff",
        ],
        wallpaperStyle: WallpaperStyle.boing.rawValue,
        icon: "circle.grid.cross",
        keywords: ["amiga", "workbench", "commodore", "kickstart", "boing", "blue", "orange", "retro"]
    )

    /// Workbench 2.0 to 3.1: grey windows, black and white bevels, blue for the selection.
    static let workbench31 = ThemeDefinition(
        name: "Amiga Workbench 3.1",
        mode: .light,
        colors: [
            "background": "#aaaaaa", "foreground": "#000000", "bright_foreground": "#000000",
            "accent": "#6688bb", "cursor": "#000000", "selection_background": "#6688bb",
            "selection_foreground": "#ffffff", "muted": "#555555", "desktop": "#aaaaaa", "highlight": "#88aadd",
            "lighter_background": "#bbbbbb", "dark_background": "#999999", "darker_background": "#777777",
            "color0": "#000000", "color7": "#aaaaaa", "color8": "#666666", "color15": "#ffffff",
            "red": "#880000", "orange": "#994400", "brown": "#553311", "yellow": "#665500",
            "green": "#005500", "cyan": "#005566", "blue": "#223388", "magenta": "#881188",
            "bright_red": "#bb0000", "bright_yellow": "#776600", "bright_green": "#116611",
            "bright_cyan": "#116677", "bright_blue": "#3355aa", "bright_magenta": "#992299",
        ],
        wallpaperStyle: WallpaperStyle.boing.rawValue,
        icon: "circle.grid.cross.fill",
        keywords: ["amiga", "workbench", "commodore", "kickstart", "boing", "gray", "grey", "retro"]
    )

    static let qnxPhoton = ThemeDefinition(
        name: "QNX Photon",
        mode: .light,
        colors: [
            "background": "#ffffff", "foreground": "#000000", "bright_foreground": "#000000",
            "accent": "#5c8bdf", "cursor": "#000000", "selection_background": "#b1c1d9",
            "selection_foreground": "#000000", "muted": "#7a7a7a", "desktop": "#7979a7", "highlight": "#b1c1d9",
            "lighter_background": "#ececec", "dark_background": "#d8d8d8", "darker_background": "#b3b3b3",
            "color0": "#000000", "color7": "#d8d8d8", "color8": "#808080", "color15": "#ffffff",
            "red": "#c0282d", "orange": "#c06000", "yellow": "#957a00", "green": "#2d7d3a",
            "cyan": "#1d7f8a", "blue": "#2a59ad", "magenta": "#8e44ad",
            "bright_red": "#e04848", "bright_yellow": "#b89500", "bright_green": "#3fa04f",
            "bright_cyan": "#2aa3b0", "bright_blue": "#5c8bdf", "bright_magenta": "#a35dc4",
        ],
        wallpaperStyle: WallpaperStyle.rain.rawValue,
        icon: "cpu",
        keywords: ["qnx", "photon", "microgui", "neutrino", "rtos", "blackberry", "periwinkle", "retro"]
    )
}
