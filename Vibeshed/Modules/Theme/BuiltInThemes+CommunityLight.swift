import Foundation

// Palettes from popular editor/terminal themes, converted from the ghostty ports in
// mbadolato/iTerm2-Color-Schemes by scripts/generate-builtin-themes.py — edit the script,
// not this file. Terminal colors (`color0`…`color15`) are kept exactly; the semantic hues
// are the readable one of each normal/bright pair, with a few overrides where a port puts
// orange in the blue/cyan slot.
extension BuiltInThemes {
    static let communityLight: [ThemeDefinition] = [
        tokyoNightDay,
        rosePineDawn,
        kanagawaLotus,
        gruvboxLight,
        githubLight,
        ayuLight,
        dawnfox,
        melangeLight,
        everforestLight,
        oneLight,
        nordLight,
    ]

    static let tokyoNightDay = ThemeDefinition(
        name: "Tokyo Night Day",
        mode: .light,
        colors: [
            "accent": "#2e7de9", "background": "#e1e2e7", "blue": "#2e7de9", "bright_blue": "#2e7de9",
            "bright_cyan": "#007197", "bright_green": "#587539", "bright_magenta": "#9854f1",
            "bright_red": "#f52a65", "bright_yellow": "#8c6c3e", "cursor": "#3760bf", "cyan": "#007197",
            "foreground": "#3760bf", "green": "#587539", "magenta": "#9854f1", "muted": "#a1a6c5",
            "red": "#f52a65", "yellow": "#8c6c3e", "color0": "#e9e9ed", "color1": "#f52a65", "color2": "#587539",
            "color3": "#8c6c3e", "color4": "#2e7de9", "color5": "#9854f1", "color6": "#007197",
            "color7": "#6172b0", "color8": "#a1a6c5", "color9": "#f52a65", "color10": "#587539",
            "color11": "#8c6c3e", "color12": "#2e7de9", "color13": "#9854f1", "color14": "#007197",
            "color15": "#3760bf",
        ],
        icon: "sun.horizon",
        keywords: ["tokyonight", "folke"]
    )

    static let rosePineDawn = ThemeDefinition(
        name: "Rosé Pine Dawn",
        mode: .light,
        colors: [
            "accent": "#d7827e", "background": "#faf4ed", "blue": "#56949f", "bright_blue": "#56949f",
            "bright_cyan": "#d7827e", "bright_green": "#286983", "bright_magenta": "#907aa9",
            "bright_red": "#b4637a", "bright_yellow": "#ea9d34", "cursor": "#575279", "cyan": "#d7827e",
            "foreground": "#575279", "green": "#286983", "magenta": "#907aa9", "muted": "#9893a5",
            "red": "#b4637a", "selection_background": "#dfdad9", "yellow": "#ea9d34", "color0": "#f2e9e1",
            "color1": "#b4637a", "color2": "#286983", "color3": "#ea9d34", "color4": "#56949f",
            "color5": "#907aa9", "color6": "#d7827e", "color7": "#575279", "color8": "#9893a5",
            "color9": "#b4637a", "color10": "#286983", "color11": "#ea9d34", "color12": "#56949f",
            "color13": "#907aa9", "color14": "#d7827e", "color15": "#575279",
        ],
        icon: "sunrise",
        keywords: ["rose", "pine", "rosepine"]
    )

    static let kanagawaLotus = ThemeDefinition(
        name: "Kanagawa Lotus",
        mode: .light,
        colors: [
            "accent": "#4d699b", "background": "#f2ecbc", "blue": "#4d699b", "bright_blue": "#6693bf",
            "bright_cyan": "#5e857a", "bright_green": "#6e915f", "bright_magenta": "#624c83",
            "bright_red": "#d7474b", "bright_yellow": "#836f4a", "cursor": "#43436c", "cyan": "#597b75",
            "foreground": "#545464", "green": "#6f894e", "magenta": "#b35b79", "muted": "#8a8980",
            "red": "#c84053", "yellow": "#77713f", "color0": "#1f1f28", "color1": "#c84053", "color2": "#6f894e",
            "color3": "#77713f", "color4": "#4d699b", "color5": "#b35b79", "color6": "#597b75",
            "color7": "#545464", "color8": "#8a8980", "color9": "#d7474b", "color10": "#6e915f",
            "color11": "#836f4a", "color12": "#6693bf", "color13": "#624c83", "color14": "#5e857a",
            "color15": "#43436c",
        ],
        icon: "leaf",
        keywords: ["kanagawa", "lotus"]
    )

    static let gruvboxLight = ThemeDefinition(
        name: "Gruvbox Light",
        mode: .light,
        colors: [
            "accent": "#af3a03", "background": "#fbf1c7", "blue": "#458588", "bright_blue": "#076678",
            "bright_cyan": "#427b58", "bright_green": "#79740e", "bright_magenta": "#8f3f71",
            "bright_red": "#9d0006", "bright_yellow": "#b57614", "cursor": "#3c3836", "cyan": "#689d6a",
            "foreground": "#3c3836", "green": "#98971a", "magenta": "#b16286", "muted": "#928374",
            "orange": "#af3a03", "red": "#cc241d", "yellow": "#b57614", "color0": "#fbf1c7", "color1": "#cc241d",
            "color2": "#98971a", "color3": "#d79921", "color4": "#458588", "color5": "#b16286",
            "color6": "#689d6a", "color7": "#7c6f64", "color8": "#928374", "color9": "#9d0006",
            "color10": "#79740e", "color11": "#b57614", "color12": "#076678", "color13": "#8f3f71",
            "color14": "#427b58", "color15": "#3c3836",
        ],
        icon: "sun.haze",
        keywords: ["gruvbox", "retro"]
    )

    static let githubLight = ThemeDefinition(
        name: "GitHub Light",
        mode: .light,
        colors: [
            "accent": "#0969da", "background": "#ffffff", "blue": "#0969da", "bright_blue": "#218bff",
            "bright_cyan": "#3192aa", "bright_green": "#1a7f37", "bright_magenta": "#a475f9",
            "bright_red": "#a40e26", "bright_yellow": "#633c01", "cursor": "#0969da", "cyan": "#1b7c83",
            "foreground": "#1f2328", "green": "#116329", "magenta": "#8250df", "muted": "#57606a",
            "red": "#cf222e", "yellow": "#4d2d00", "color0": "#24292f", "color1": "#cf222e", "color2": "#116329",
            "color3": "#4d2d00", "color4": "#0969da", "color5": "#8250df", "color6": "#1b7c83",
            "color7": "#6e7781", "color8": "#57606a", "color9": "#a40e26", "color10": "#1a7f37",
            "color11": "#633c01", "color12": "#218bff", "color13": "#a475f9", "color14": "#3192aa",
            "color15": "#8c959f",
        ],
        icon: "arrow.triangle.pull",
        keywords: ["github", "primer"]
    )

    static let ayuLight = ThemeDefinition(
        name: "Ayu Light",
        mode: .light,
        colors: [
            "accent": "#ff9940", "background": "#f8f9fa", "blue": "#3199e1", "bright_blue": "#399ee6",
            "bright_cyan": "#4cbf99", "bright_green": "#86b300", "bright_magenta": "#a37acc",
            "bright_red": "#f07171", "bright_yellow": "#f2ae49", "cyan": "#46ba94", "foreground": "#5c6166",
            "green": "#86b300", "magenta": "#9e75c7", "muted": "#686868", "red": "#ea6c6d", "yellow": "#eca944",
            "color0": "#000000", "color1": "#ea6c6d", "color2": "#6cbf43", "color3": "#eca944",
            "color4": "#3199e1", "color5": "#9e75c7", "color6": "#46ba94", "color7": "#bababa",
            "color8": "#686868", "color9": "#f07171", "color10": "#86b300", "color11": "#f2ae49",
            "color12": "#399ee6", "color13": "#a37acc", "color14": "#4cbf99", "color15": "#d1d1d1",
        ],
        icon: "sun.min",
        keywords: ["ayu"]
    )

    static let dawnfox = ThemeDefinition(
        name: "Dawnfox",
        mode: .light,
        colors: [
            "accent": "#286983", "background": "#faf4ed", "blue": "#286983", "bright_blue": "#2d81a3",
            "bright_cyan": "#5ca7b4", "bright_green": "#629f81", "bright_magenta": "#9a80b9",
            "bright_red": "#c26d85", "bright_yellow": "#eea846", "cursor": "#575279", "cyan": "#56949f",
            "foreground": "#575279", "green": "#618774", "magenta": "#907aa9", "muted": "#5f5695",
            "red": "#b4637a", "selection_background": "#d0d8d8", "yellow": "#ea9d34", "color0": "#575279",
            "color1": "#b4637a", "color2": "#618774", "color3": "#ea9d34", "color4": "#286983",
            "color5": "#907aa9", "color6": "#56949f", "color7": "#b2b6bd", "color8": "#5f5695",
            "color9": "#c26d85", "color10": "#629f81", "color11": "#eea846", "color12": "#2d81a3",
            "color13": "#9a80b9", "color14": "#5ca7b4", "color15": "#e6ebf3",
        ],
        icon: "pawprint.circle",
        keywords: ["nightfox", "fox"]
    )

    static let melangeLight = ThemeDefinition(
        name: "Melange Light",
        mode: .light,
        colors: [
            "accent": "#bc5c00", "background": "#f1f1f1", "blue": "#7892bd", "bright_blue": "#465aa4",
            "bright_cyan": "#3d6568", "bright_green": "#3a684a", "bright_magenta": "#904180",
            "bright_red": "#bf0021", "bright_yellow": "#a06d00", "cursor": "#54433a", "cyan": "#739797",
            "foreground": "#54433a", "green": "#6e9b72", "magenta": "#be79bb", "muted": "#a98a78",
            "orange": "#bc5c00", "red": "#c77b8b", "yellow": "#bc5c00", "color0": "#e9e1db", "color1": "#c77b8b",
            "color2": "#6e9b72", "color3": "#bc5c00", "color4": "#7892bd", "color5": "#be79bb",
            "color6": "#739797", "color7": "#7d6658", "color8": "#a98a78", "color9": "#bf0021",
            "color10": "#3a684a", "color11": "#a06d00", "color12": "#465aa4", "color13": "#904180",
            "color14": "#3d6568", "color15": "#54433a",
        ],
        icon: "mug",
        keywords: ["melange", "warm"]
    )

    static let everforestLight = ThemeDefinition(
        name: "Everforest Light",
        mode: .light,
        colors: [
            "accent": "#8da101", "background": "#efebd4", "blue": "#3a94c5", "bright_blue": "#3a94c5",
            "bright_cyan": "#35a77c", "bright_green": "#8da101", "bright_magenta": "#df69ba",
            "bright_red": "#f85552", "bright_yellow": "#dfa000", "cyan": "#35a77c", "foreground": "#5c6a72",
            "green": "#8da101", "magenta": "#df69ba", "muted": "#a6b0a0", "red": "#f85552",
            "selection_background": "#eaedc8", "yellow": "#c1a266", "color0": "#7a8478", "color1": "#e67e80",
            "color2": "#9ab373", "color3": "#c1a266", "color4": "#7fbbb3", "color5": "#d699b6",
            "color6": "#83c092", "color7": "#b2af9f", "color8": "#a6b0a0", "color9": "#f85552",
            "color10": "#8da101", "color11": "#dfa000", "color12": "#3a94c5", "color13": "#df69ba",
            "color14": "#35a77c", "color15": "#fffbef",
        ],
        icon: "leaf.fill",
        keywords: ["everforest", "forest", "green"]
    )

    static let oneLight = ThemeDefinition(
        name: "One Light",
        mode: .light,
        colors: [
            "accent": "#2f5af3", "background": "#f9f9f9", "blue": "#2f5af3", "bright_blue": "#2f5af3",
            "bright_cyan": "#3f953a", "bright_green": "#3f953a", "bright_magenta": "#a00095",
            "bright_red": "#de3e35", "bright_yellow": "#d2b67c", "cyan": "#3f953a", "foreground": "#2a2c33",
            "green": "#3f953a", "magenta": "#950095", "muted": "#87888c", "red": "#de3e35",
            "selection_background": "#ededed", "yellow": "#d2b67c", "color0": "#000000", "color1": "#de3e35",
            "color2": "#3f953a", "color3": "#d2b67c", "color4": "#2f5af3", "color5": "#950095",
            "color6": "#3f953a", "color7": "#bbbbbb", "color8": "#000000", "color9": "#de3e35",
            "color10": "#3f953a", "color11": "#d2b67c", "color12": "#2f5af3", "color13": "#a00095",
            "color14": "#3f953a", "color15": "#ffffff",
        ],
        icon: "atom",
        keywords: ["onelight", "atom"]
    )

    static let nordLight = ThemeDefinition(
        name: "Nord Light",
        mode: .light,
        colors: [
            "accent": "#5e81ac", "background": "#e5e9f0", "blue": "#81a1c1", "bright_blue": "#81a1c1",
            "bright_cyan": "#82afae", "bright_green": "#96b17f", "bright_magenta": "#b48ead",
            "bright_red": "#bf616a", "bright_yellow": "#c5a565", "cyan": "#82afae", "foreground": "#414858",
            "green": "#96b17f", "magenta": "#b48ead", "muted": "#4c566a", "red": "#bf616a",
            "selection_background": "#d8dee9", "yellow": "#c5a565", "color0": "#3b4252", "color1": "#bf616a",
            "color2": "#96b17f", "color3": "#c5a565", "color4": "#81a1c1", "color5": "#b48ead",
            "color6": "#7bb3c3", "color7": "#a5abb6", "color8": "#4c566a", "color9": "#bf616a",
            "color10": "#96b17f", "color11": "#c5a565", "color12": "#81a1c1", "color13": "#b48ead",
            "color14": "#82afae", "color15": "#eceff4",
        ],
        icon: "snowflake",
        keywords: ["nord", "arctic"]
    )
}
