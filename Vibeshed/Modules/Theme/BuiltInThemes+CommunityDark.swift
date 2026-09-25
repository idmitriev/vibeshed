import Foundation

// Palettes from popular editor/terminal themes, converted from the ghostty ports in
// mbadolato/iTerm2-Color-Schemes by scripts/generate-builtin-themes.py — edit the script,
// not this file. Terminal colors (`color0`…`color15`) are kept exactly; the semantic hues
// are the readable one of each normal/bright pair, with a few overrides where a port puts
// orange in the blue/cyan slot.
extension BuiltInThemes {
    static let communityDark: [ThemeDefinition] = [
        catppuccinFrappe,
        catppuccinMacchiato,
        tokyoNightStorm,
        tokyoNightMoon,
        rosePineMoon,
        kanagawaDragon,
        gruvboxMaterial,
        solarizedDark,
        githubDark,
        githubDarkDimmed,
        ayuDark,
        ayuMirage,
        nightfox,
        carbonfox,
        nightOwl,
        monokaiPro,
        poimandres,
        vesper,
        flexokiDark,
        moonfly,
        sonokai,
        iceberg,
        melangeDark,
        vague,
    ]

    static let catppuccinFrappe = ThemeDefinition(
        name: "Catppuccin Frappé",
        mode: .dark,
        colors: [
            "accent": "#ca9ee6", "background": "#303446", "blue": "#8caaee", "bright_blue": "#adc2f3",
            "bright_cyan": "#98d2ca", "bright_green": "#b9dba2", "bright_magenta": "#f4b8e4",
            "bright_red": "#eda0a2", "bright_yellow": "#ecd7ae", "cursor": "#f2d5cf", "cyan": "#81c8be",
            "foreground": "#c6d0f5", "green": "#a6d189", "magenta": "#f4b8e4", "muted": "#626880",
            "red": "#e78284", "yellow": "#e5c890", "color0": "#51576d", "color1": "#e78284", "color2": "#a6d189",
            "color3": "#e5c890", "color4": "#8caaee", "color5": "#f4b8e4", "color6": "#81c8be",
            "color7": "#b5bfe2", "color8": "#626880", "color9": "#eda0a2", "color10": "#b9dba2",
            "color11": "#ecd7ae", "color12": "#adc2f3", "color13": "#f38ed8", "color14": "#98d2ca",
            "color15": "#a5adce",
        ],
        icon: "cup.and.saucer",
        keywords: ["catppuccin", "frappe", "pastel"]
    )

    static let catppuccinMacchiato = ThemeDefinition(
        name: "Catppuccin Macchiato",
        mode: .dark,
        colors: [
            "accent": "#c6a0f6", "background": "#24273a", "blue": "#8aadf4", "bright_blue": "#adc5f7",
            "bright_cyan": "#a5ded6", "bright_green": "#bde3b0", "bright_magenta": "#f5bde6",
            "bright_red": "#f2a7b2", "bright_yellow": "#f4e3c1", "cursor": "#f4dbd6", "cyan": "#8bd5ca",
            "foreground": "#cad3f5", "green": "#a6da95", "magenta": "#f5bde6", "muted": "#5b6078",
            "red": "#ed8796", "yellow": "#eed49f", "color0": "#494d64", "color1": "#ed8796", "color2": "#a6da95",
            "color3": "#eed49f", "color4": "#8aadf4", "color5": "#f5bde6", "color6": "#8bd5ca",
            "color7": "#b8c0e0", "color8": "#5b6078", "color9": "#f2a7b2", "color10": "#bde3b0",
            "color11": "#f4e3c1", "color12": "#adc5f7", "color13": "#f493da", "color14": "#a5ded6",
            "color15": "#a5adcb",
        ],
        icon: "cup.and.saucer.fill",
        keywords: ["catppuccin", "pastel"]
    )

    static let tokyoNightStorm = ThemeDefinition(
        name: "Tokyo Night Storm",
        mode: .dark,
        colors: [
            "accent": "#7aa2f7", "background": "#24283b", "blue": "#7aa2f7", "bright_blue": "#7aa2f7",
            "bright_cyan": "#7dcfff", "bright_green": "#9ece6a", "bright_magenta": "#bb9af7",
            "bright_red": "#f7768e", "bright_yellow": "#e0af68", "cursor": "#c0caf5", "cyan": "#7dcfff",
            "foreground": "#c0caf5", "green": "#9ece6a", "magenta": "#bb9af7", "muted": "#4e5575",
            "red": "#f7768e", "selection_background": "#364a82", "yellow": "#e0af68", "color0": "#1d202f",
            "color1": "#f7768e", "color2": "#9ece6a", "color3": "#e0af68", "color4": "#7aa2f7",
            "color5": "#bb9af7", "color6": "#7dcfff", "color7": "#a9b1d6", "color8": "#4e5575",
            "color9": "#f7768e", "color10": "#9ece6a", "color11": "#e0af68", "color12": "#7aa2f7",
            "color13": "#bb9af7", "color14": "#7dcfff", "color15": "#c0caf5",
        ],
        icon: "cloud.bolt",
        keywords: ["tokyonight", "folke"]
    )

    static let tokyoNightMoon = ThemeDefinition(
        name: "Tokyo Night Moon",
        mode: .dark,
        colors: [
            "accent": "#82aaff", "background": "#222436", "blue": "#82aaff", "bright_blue": "#82aaff",
            "bright_cyan": "#86e1fc", "bright_green": "#c3e88d", "bright_magenta": "#c099ff",
            "bright_red": "#ff757f", "bright_yellow": "#ffc777", "cursor": "#c8d3f5", "cyan": "#86e1fc",
            "foreground": "#c8d3f5", "green": "#c3e88d", "magenta": "#c099ff", "muted": "#444a73",
            "red": "#ff757f", "selection_background": "#2d3f76", "yellow": "#ffc777", "color0": "#1b1d2b",
            "color1": "#ff757f", "color2": "#c3e88d", "color3": "#ffc777", "color4": "#82aaff",
            "color5": "#c099ff", "color6": "#86e1fc", "color7": "#828bb8", "color8": "#444a73",
            "color9": "#ff757f", "color10": "#c3e88d", "color11": "#ffc777", "color12": "#82aaff",
            "color13": "#c099ff", "color14": "#86e1fc", "color15": "#c8d3f5",
        ],
        icon: "moon",
        keywords: ["tokyonight", "folke"]
    )

    static let rosePineMoon = ThemeDefinition(
        name: "Rosé Pine Moon",
        mode: .dark,
        colors: [
            "accent": "#ea9a97", "background": "#232136", "blue": "#9ccfd8", "bright_blue": "#9ccfd8",
            "bright_cyan": "#ea9a97", "bright_green": "#3e8fb0", "bright_magenta": "#c4a7e7",
            "bright_red": "#eb6f92", "bright_yellow": "#f6c177", "cursor": "#e0def4", "cyan": "#ea9a97",
            "foreground": "#e0def4", "green": "#3e8fb0", "magenta": "#c4a7e7", "muted": "#6e6a86",
            "red": "#eb6f92", "selection_background": "#44415a", "yellow": "#f6c177", "color0": "#393552",
            "color1": "#eb6f92", "color2": "#3e8fb0", "color3": "#f6c177", "color4": "#9ccfd8",
            "color5": "#c4a7e7", "color6": "#ea9a97", "color7": "#e0def4", "color8": "#6e6a86",
            "color9": "#eb6f92", "color10": "#3e8fb0", "color11": "#f6c177", "color12": "#9ccfd8",
            "color13": "#c4a7e7", "color14": "#ea9a97", "color15": "#e0def4",
        ],
        icon: "moon.haze",
        keywords: ["rose", "pine", "rosepine"]
    )

    static let kanagawaDragon = ThemeDefinition(
        name: "Kanagawa Dragon",
        mode: .dark,
        colors: [
            "accent": "#8ba4b0", "background": "#181616", "blue": "#8ba4b0", "bright_blue": "#7fb4ca",
            "bright_cyan": "#8ea4a2", "bright_green": "#87a987", "bright_magenta": "#a292a3",
            "bright_red": "#e46876", "bright_yellow": "#e6c384", "cursor": "#c8c093", "cyan": "#8ea4a2",
            "foreground": "#c5c9c5", "green": "#8a9a7b", "magenta": "#a292a3", "muted": "#a6a69c",
            "red": "#c4746e", "yellow": "#c4b28a", "color0": "#0d0c0c", "color1": "#c4746e", "color2": "#8a9a7b",
            "color3": "#c4b28a", "color4": "#8ba4b0", "color5": "#a292a3", "color6": "#8ea4a2",
            "color7": "#c8c093", "color8": "#a6a69c", "color9": "#e46876", "color10": "#87a987",
            "color11": "#e6c384", "color12": "#7fb4ca", "color13": "#938aa9", "color14": "#7aa89f",
            "color15": "#c5c9c5",
        ],
        icon: "lizard",
        keywords: ["kanagawa", "dragon"]
    )

    static let gruvboxMaterial = ThemeDefinition(
        name: "Gruvbox Material",
        mode: .dark,
        colors: [
            "accent": "#e78a4e", "background": "#282828", "blue": "#7daea3", "bright_blue": "#7daea3",
            "bright_cyan": "#89b482", "bright_green": "#a9b665", "bright_magenta": "#d3869b",
            "bright_red": "#ea6962", "bright_yellow": "#d8a657", "cursor": "#d4be98", "cyan": "#89b482",
            "foreground": "#d4be98", "green": "#a9b665", "magenta": "#d3869b", "muted": "#7c6f64",
            "orange": "#e78a4e", "red": "#ea6962", "yellow": "#d8a657", "color0": "#282828", "color1": "#ea6962",
            "color2": "#a9b665", "color3": "#d8a657", "color4": "#7daea3", "color5": "#d3869b",
            "color6": "#89b482", "color7": "#d4be98", "color8": "#7c6f64", "color9": "#ea6962",
            "color10": "#a9b665", "color11": "#d8a657", "color12": "#7daea3", "color13": "#d3869b",
            "color14": "#89b482", "color15": "#ddc7a1",
        ],
        icon: "flame.fill",
        keywords: ["gruvbox", "material", "retro"]
    )

    static let solarizedDark = ThemeDefinition(
        name: "Solarized Dark",
        mode: .dark,
        colors: [
            "accent": "#268bd2", "background": "#002b36", "blue": "#268bd2", "bright_blue": "#268bd2",
            "bright_cyan": "#2aa198", "bright_foreground": "#93a1a1", "bright_green": "#859900",
            "bright_magenta": "#d33682", "bright_red": "#dc322f", "bright_yellow": "#b58900", "cursor": "#839496",
            "cyan": "#2aa198", "foreground": "#839496", "green": "#859900", "magenta": "#d33682",
            "muted": "#586e75", "orange": "#cb4b16", "red": "#dc322f", "selection_background": "#073642",
            "yellow": "#b58900", "color0": "#073642", "color1": "#dc322f", "color2": "#859900",
            "color3": "#b58900", "color4": "#268bd2", "color5": "#d33682", "color6": "#2aa198",
            "color7": "#eee8d5", "color8": "#335e69", "color9": "#cb4b16", "color10": "#586e75",
            "color11": "#657b83", "color12": "#839496", "color13": "#6c71c4", "color14": "#93a1a1",
            "color15": "#fdf6e3",
        ],
        icon: "moon.circle",
        keywords: ["solarized"]
    )

    static let githubDark = ThemeDefinition(
        name: "GitHub Dark",
        mode: .dark,
        colors: [
            "accent": "#58a6ff", "background": "#0d1117", "blue": "#58a6ff", "bright_blue": "#79c0ff",
            "bright_cyan": "#56d4dd", "bright_green": "#56d364", "bright_magenta": "#d2a8ff",
            "bright_red": "#ffa198", "bright_yellow": "#e3b341", "cursor": "#2f81f7", "cyan": "#39c5cf",
            "foreground": "#e6edf3", "green": "#3fb950", "magenta": "#bc8cff", "muted": "#6e7681",
            "red": "#ff7b72", "yellow": "#d29922", "color0": "#484f58", "color1": "#ff7b72", "color2": "#3fb950",
            "color3": "#d29922", "color4": "#58a6ff", "color5": "#bc8cff", "color6": "#39c5cf",
            "color7": "#b1bac4", "color8": "#6e7681", "color9": "#ffa198", "color10": "#56d364",
            "color11": "#e3b341", "color12": "#79c0ff", "color13": "#d2a8ff", "color14": "#56d4dd",
            "color15": "#ffffff",
        ],
        icon: "arrow.triangle.branch",
        keywords: ["github", "primer"]
    )

    static let githubDarkDimmed = ThemeDefinition(
        name: "GitHub Dark Dimmed",
        mode: .dark,
        colors: [
            "accent": "#539bf5", "background": "#22272e", "blue": "#539bf5", "bright_blue": "#6cb6ff",
            "bright_cyan": "#56d4dd", "bright_green": "#6bc46d", "bright_magenta": "#dcbdfb",
            "bright_red": "#ff938a", "bright_yellow": "#daaa3f", "cursor": "#539bf5", "cyan": "#39c5cf",
            "foreground": "#adbac7", "green": "#57ab5a", "magenta": "#b083f0", "muted": "#636e7b",
            "red": "#f47067", "yellow": "#c69026", "color0": "#545d68", "color1": "#f47067", "color2": "#57ab5a",
            "color3": "#c69026", "color4": "#539bf5", "color5": "#b083f0", "color6": "#39c5cf",
            "color7": "#909dab", "color8": "#636e7b", "color9": "#ff938a", "color10": "#6bc46d",
            "color11": "#daaa3f", "color12": "#6cb6ff", "color13": "#dcbdfb", "color14": "#56d4dd",
            "color15": "#cdd9e5",
        ],
        icon: "arrow.triangle.merge",
        keywords: ["github", "primer", "dimmed"]
    )

    static let ayuDark = ThemeDefinition(
        name: "Ayu Dark",
        mode: .dark,
        colors: [
            "accent": "#e6b450", "background": "#0b0e14", "blue": "#53bdfa", "bright_blue": "#59c2ff",
            "bright_cyan": "#95e6cb", "bright_green": "#aad94c", "bright_magenta": "#d2a6ff",
            "bright_red": "#f07178", "bright_yellow": "#ffb454", "cursor": "#e6b450", "cyan": "#90e1c6",
            "foreground": "#bfbdb6", "green": "#7fd962", "magenta": "#cda1fa", "muted": "#686868",
            "red": "#ea6c73", "yellow": "#f9af4f", "color0": "#11151c", "color1": "#ea6c73", "color2": "#7fd962",
            "color3": "#f9af4f", "color4": "#53bdfa", "color5": "#cda1fa", "color6": "#90e1c6",
            "color7": "#c7c7c7", "color8": "#686868", "color9": "#f07178", "color10": "#aad94c",
            "color11": "#ffb454", "color12": "#59c2ff", "color13": "#d2a6ff", "color14": "#95e6cb",
            "color15": "#ffffff",
        ],
        icon: "moon.dust",
        keywords: ["ayu"]
    )

    static let ayuMirage = ThemeDefinition(
        name: "Ayu Mirage",
        mode: .dark,
        colors: [
            "accent": "#ffcc66", "background": "#1f2430", "blue": "#6dcbfa", "bright_blue": "#73d0ff",
            "bright_cyan": "#95e6cb", "bright_green": "#d5ff80", "bright_magenta": "#dfbfff",
            "bright_red": "#f28779", "bright_yellow": "#ffd173", "cursor": "#ffcc66", "cyan": "#90e1c6",
            "foreground": "#cccac2", "green": "#87d96c", "magenta": "#dabafa", "muted": "#686868",
            "red": "#ed8274", "yellow": "#facc6e", "color0": "#171b24", "color1": "#ed8274", "color2": "#87d96c",
            "color3": "#facc6e", "color4": "#6dcbfa", "color5": "#dabafa", "color6": "#90e1c6",
            "color7": "#c7c7c7", "color8": "#686868", "color9": "#f28779", "color10": "#d5ff80",
            "color11": "#ffd173", "color12": "#73d0ff", "color13": "#dfbfff", "color14": "#95e6cb",
            "color15": "#ffffff",
        ],
        icon: "cloud.moon",
        keywords: ["ayu", "mirage"]
    )

    static let nightfox = ThemeDefinition(
        name: "Nightfox",
        mode: .dark,
        colors: [
            "accent": "#719cd6", "background": "#192330", "blue": "#719cd6", "bright_blue": "#86abdc",
            "bright_cyan": "#7ad5d6", "bright_green": "#8ebaa4", "bright_magenta": "#baa1e2",
            "bright_red": "#d16983", "bright_yellow": "#e0c989", "cursor": "#cdcecf", "cyan": "#63cdcf",
            "foreground": "#cdcecf", "green": "#81b29a", "magenta": "#9d79d6", "muted": "#575860",
            "red": "#c94f6d", "selection_background": "#2b3b51", "yellow": "#dbc074", "color0": "#393b44",
            "color1": "#c94f6d", "color2": "#81b29a", "color3": "#dbc074", "color4": "#719cd6",
            "color5": "#9d79d6", "color6": "#63cdcf", "color7": "#dfdfe0", "color8": "#575860",
            "color9": "#d16983", "color10": "#8ebaa4", "color11": "#e0c989", "color12": "#86abdc",
            "color13": "#baa1e2", "color14": "#7ad5d6", "color15": "#e4e4e5",
        ],
        icon: "pawprint",
        keywords: ["nightfox", "fox"]
    )

    static let carbonfox = ThemeDefinition(
        name: "Carbonfox",
        mode: .dark,
        colors: [
            "accent": "#78a9ff", "background": "#161616", "blue": "#78a9ff", "bright_blue": "#8cb6ff",
            "bright_cyan": "#52bdff", "bright_green": "#46c880", "bright_magenta": "#c8a5ff",
            "bright_red": "#f16da6", "bright_yellow": "#2dc7c4", "cursor": "#f2f4f8", "cyan": "#33b1ff",
            "foreground": "#f2f4f8", "green": "#25be6a", "magenta": "#be95ff", "muted": "#484848",
            "red": "#ee5396", "selection_background": "#2a2a2a", "yellow": "#08bdba", "color0": "#282828",
            "color1": "#ee5396", "color2": "#25be6a", "color3": "#08bdba", "color4": "#78a9ff",
            "color5": "#be95ff", "color6": "#33b1ff", "color7": "#dfdfe0", "color8": "#484848",
            "color9": "#f16da6", "color10": "#46c880", "color11": "#2dc7c4", "color12": "#8cb6ff",
            "color13": "#c8a5ff", "color14": "#52bdff", "color15": "#e4e4e5",
        ],
        icon: "pawprint.fill",
        keywords: ["nightfox", "fox", "carbon"]
    )

    static let nightOwl = ThemeDefinition(
        name: "Night Owl",
        mode: .dark,
        colors: [
            "accent": "#82aaff", "background": "#011627", "blue": "#82aaff", "bright_blue": "#82aaff",
            "bright_cyan": "#7fdbca", "bright_green": "#22da6e", "bright_magenta": "#c792ea",
            "bright_red": "#ef5350", "bright_yellow": "#ffeb95", "cursor": "#7e57c2", "cyan": "#21c7a8",
            "foreground": "#d6deeb", "green": "#22da6e", "magenta": "#c792ea", "muted": "#575656",
            "red": "#ef5350", "selection_background": "#5f7e97", "yellow": "#addb67", "color0": "#011627",
            "color1": "#ef5350", "color2": "#22da6e", "color3": "#addb67", "color4": "#82aaff",
            "color5": "#c792ea", "color6": "#21c7a8", "color7": "#ffffff", "color8": "#575656",
            "color9": "#ef5350", "color10": "#22da6e", "color11": "#ffeb95", "color12": "#82aaff",
            "color13": "#c792ea", "color14": "#7fdbca", "color15": "#ffffff",
        ],
        icon: "bird",
        keywords: ["owl", "sarah drasner"]
    )

    static let monokaiPro = ThemeDefinition(
        name: "Monokai Pro",
        mode: .dark,
        colors: [
            "accent": "#ffd866", "background": "#2d2a2e", "blue": "#78dce8", "bright_blue": "#78dce8",
            "bright_cyan": "#78dce8", "bright_green": "#a9dc76", "bright_magenta": "#ab9df2",
            "bright_red": "#ff6188", "bright_yellow": "#ffd866", "cursor": "#c1c0c0", "cyan": "#78dce8",
            "foreground": "#fcfcfa", "green": "#a9dc76", "magenta": "#ab9df2", "muted": "#727072",
            "orange": "#fc9867", "red": "#ff6188", "selection_background": "#5b595c", "yellow": "#ffd866",
            "color0": "#2d2a2e", "color1": "#ff6188", "color2": "#a9dc76", "color3": "#ffd866",
            "color4": "#fc9867", "color5": "#ab9df2", "color6": "#78dce8", "color7": "#fcfcfa",
            "color8": "#727072", "color9": "#ff6188", "color10": "#a9dc76", "color11": "#ffd866",
            "color12": "#fc9867", "color13": "#ab9df2", "color14": "#78dce8", "color15": "#fcfcfa",
        ],
        icon: "square.stack.3d.up",
        keywords: ["monokai"]
    )

    static let poimandres = ThemeDefinition(
        name: "Poimandres",
        mode: .dark,
        colors: [
            "accent": "#5de4c7", "background": "#1a1e28", "blue": "#89ddff", "bright_blue": "#add7ff",
            "bright_cyan": "#add7ff", "bright_green": "#5de4c7", "bright_magenta": "#fae4fc",
            "bright_red": "#d0679d", "bright_yellow": "#fffac2", "cursor": "#ffffff", "cyan": "#add7ff",
            "foreground": "#a6accd", "green": "#5de4c7", "magenta": "#fcc5e9", "muted": "#676c83",
            "red": "#d0679d", "yellow": "#fffac2", "color0": "#1a1e28", "color1": "#d0679d", "color2": "#5de4c7",
            "color3": "#fffac2", "color4": "#89ddff", "color5": "#fcc5e9", "color6": "#add7ff",
            "color7": "#ffffff", "color8": "#a6accd", "color9": "#d0679d", "color10": "#5de4c7",
            "color11": "#fffac2", "color12": "#add7ff", "color13": "#fae4fc", "color14": "#89ddff",
            "color15": "#ffffff",
        ],
        icon: "sparkles",
        keywords: ["poimandres", "mint"]
    )

    static let vesper = ThemeDefinition(
        name: "Vesper",
        mode: .dark,
        colors: [
            "accent": "#ffc799", "background": "#101010", "blue": "#aca1cf", "bright_blue": "#b9aeda",
            "bright_cyan": "#99ffe4", "bright_green": "#99ffe4", "bright_magenta": "#ecaad6",
            "bright_red": "#f5a191", "bright_yellow": "#ffc799", "cursor": "#acb1ab", "cyan": "#99ffe4",
            "foreground": "#ffffff", "green": "#90b99f", "magenta": "#e29eca", "muted": "#7e7e7e",
            "red": "#f5a191", "selection_background": "#988049", "yellow": "#e6b99d", "color0": "#101010",
            "color1": "#f5a191", "color2": "#90b99f", "color3": "#e6b99d", "color4": "#aca1cf",
            "color5": "#e29eca", "color6": "#ea83a5", "color7": "#a0a0a0", "color8": "#7e7e7e",
            "color9": "#ff8080", "color10": "#99ffe4", "color11": "#ffc799", "color12": "#b9aeda",
            "color13": "#ecaad6", "color14": "#f591b2", "color15": "#ffffff",
        ],
        icon: "star",
        keywords: ["vesper", "minimal", "orange"]
    )

    static let flexokiDark = ThemeDefinition(
        name: "Flexoki Dark",
        mode: .dark,
        colors: [
            "accent": "#4385be", "background": "#100f0f", "blue": "#4385be", "bright_blue": "#4385be",
            "bright_cyan": "#3aa99f", "bright_green": "#879a39", "bright_magenta": "#ce5d97",
            "bright_red": "#d14d41", "bright_yellow": "#d0a215", "cursor": "#cecdc3", "cyan": "#3aa99f",
            "foreground": "#cecdc3", "green": "#879a39", "magenta": "#ce5d97", "muted": "#575653",
            "red": "#d14d41", "selection_background": "#403e3c", "yellow": "#d0a215", "color0": "#100f0f",
            "color1": "#d14d41", "color2": "#879a39", "color3": "#d0a215", "color4": "#4385be",
            "color5": "#ce5d97", "color6": "#3aa99f", "color7": "#878580", "color8": "#575653",
            "color9": "#af3029", "color10": "#66800b", "color11": "#ad8301", "color12": "#205ea6",
            "color13": "#a02f6f", "color14": "#24837b", "color15": "#cecdc3",
        ],
        icon: "book.closed",
        keywords: ["flexoki", "paper"]
    )

    static let moonfly = ThemeDefinition(
        name: "Moonfly",
        mode: .dark,
        colors: [
            "accent": "#80a0ff", "background": "#080808", "blue": "#80a0ff", "bright_blue": "#74b2ff",
            "bright_cyan": "#79dac8", "bright_green": "#8cc85f", "bright_magenta": "#cf87e8",
            "bright_red": "#ff5189", "bright_yellow": "#e3c78a", "cursor": "#9e9e9e", "cyan": "#79dac8",
            "foreground": "#bdbdbd", "green": "#8cc85f", "magenta": "#cf87e8", "muted": "#949494",
            "red": "#ff5454", "yellow": "#e3c78a", "color0": "#323437", "color1": "#ff5454", "color2": "#8cc85f",
            "color3": "#e3c78a", "color4": "#80a0ff", "color5": "#cf87e8", "color6": "#79dac8",
            "color7": "#c6c6c6", "color8": "#949494", "color9": "#ff5189", "color10": "#36c692",
            "color11": "#c6c684", "color12": "#74b2ff", "color13": "#ae81ff", "color14": "#85dc85",
            "color15": "#e4e4e4",
        ],
        icon: "moonphase.waxing.crescent",
        keywords: ["moonfly", "bluz71"]
    )

    static let sonokai = ThemeDefinition(
        name: "Sonokai",
        mode: .dark,
        colors: [
            "accent": "#76cce0", "background": "#2c2e34", "blue": "#76cce0", "bright_blue": "#76cce0",
            "bright_cyan": "#76cce0", "bright_green": "#9ed072", "bright_magenta": "#b39df3",
            "bright_red": "#fc5d7c", "bright_yellow": "#e7c664", "cursor": "#e2e2e3", "cyan": "#76cce0",
            "foreground": "#e2e2e3", "green": "#9ed072", "magenta": "#b39df3", "muted": "#7f8490",
            "orange": "#f39660", "red": "#fc5d7c", "selection_background": "#414550", "yellow": "#e7c664",
            "color0": "#181819", "color1": "#fc5d7c", "color2": "#9ed072", "color3": "#e7c664",
            "color4": "#76cce0", "color5": "#b39df3", "color6": "#f39660", "color7": "#e2e2e3",
            "color8": "#7f8490", "color9": "#fc5d7c", "color10": "#9ed072", "color11": "#e7c664",
            "color12": "#76cce0", "color13": "#b39df3", "color14": "#f39660", "color15": "#e2e2e3",
        ],
        icon: "waveform",
        keywords: ["sonokai", "monokai"]
    )

    static let iceberg = ThemeDefinition(
        name: "Iceberg",
        mode: .dark,
        colors: [
            "accent": "#84a0c6", "background": "#161821", "blue": "#84a0c6", "bright_blue": "#91acd1",
            "bright_cyan": "#95c4ce", "bright_green": "#c0ca8e", "bright_magenta": "#ada0d3",
            "bright_red": "#e98989", "bright_yellow": "#e9b189", "cursor": "#c6c8d1", "cyan": "#89b8c2",
            "foreground": "#c6c8d1", "green": "#b4be82", "magenta": "#a093c7", "muted": "#6b7089",
            "red": "#e27878", "yellow": "#e2a478", "color0": "#1e2132", "color1": "#e27878", "color2": "#b4be82",
            "color3": "#e2a478", "color4": "#84a0c6", "color5": "#a093c7", "color6": "#89b8c2",
            "color7": "#c6c8d1", "color8": "#6b7089", "color9": "#e98989", "color10": "#c0ca8e",
            "color11": "#e9b189", "color12": "#91acd1", "color13": "#ada0d3", "color14": "#95c4ce",
            "color15": "#d2d4de",
        ],
        icon: "snowflake.circle",
        keywords: ["iceberg", "cool"]
    )

    static let melangeDark = ThemeDefinition(
        name: "Melange Dark",
        mode: .dark,
        colors: [
            "accent": "#e49b5d", "background": "#292522", "blue": "#7f91b2", "bright_blue": "#a3a9ce",
            "bright_cyan": "#89b3b6", "bright_green": "#85b695", "bright_magenta": "#cf9bc2",
            "bright_red": "#bd8183", "bright_yellow": "#ebc06d", "cursor": "#ece1d7", "cyan": "#7b9695",
            "foreground": "#ece1d7", "green": "#78997a", "magenta": "#b380b0", "muted": "#867462",
            "orange": "#e49b5d", "red": "#bd8183", "yellow": "#ebc06d", "color0": "#34302c", "color1": "#bd8183",
            "color2": "#78997a", "color3": "#e49b5d", "color4": "#7f91b2", "color5": "#b380b0",
            "color6": "#7b9695", "color7": "#c1a78e", "color8": "#867462", "color9": "#d47766",
            "color10": "#85b695", "color11": "#ebc06d", "color12": "#a3a9ce", "color13": "#cf9bc2",
            "color14": "#89b3b6", "color15": "#ece1d7",
        ],
        icon: "mug.fill",
        keywords: ["melange", "warm"]
    )

    static let vague = ThemeDefinition(
        name: "Vague",
        mode: .dark,
        colors: [
            "accent": "#6e94b2", "background": "#141415", "blue": "#6e94b2", "bright_blue": "#8ba9c1",
            "bright_cyan": "#bebeda", "bright_green": "#99b782", "bright_magenta": "#c9b1ca",
            "bright_red": "#e08398", "bright_yellow": "#f5cb96", "cursor": "#cdcdcd", "cyan": "#aeaed1",
            "foreground": "#cdcdcd", "green": "#7fa563", "magenta": "#bb9dbd", "muted": "#606079",
            "red": "#d8647e", "selection_background": "#252530", "yellow": "#f3be7c", "color0": "#252530",
            "color1": "#d8647e", "color2": "#7fa563", "color3": "#f3be7c", "color4": "#6e94b2",
            "color5": "#bb9dbd", "color6": "#aeaed1", "color7": "#cdcdcd", "color8": "#606079",
            "color9": "#e08398", "color10": "#99b782", "color11": "#f5cb96", "color12": "#8ba9c1",
            "color13": "#c9b1ca", "color14": "#bebeda", "color15": "#d7d7d7",
        ],
        icon: "cloud.fog",
        keywords: ["vague", "muted"]
    )
}
