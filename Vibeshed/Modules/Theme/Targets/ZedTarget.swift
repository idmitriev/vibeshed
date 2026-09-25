import Foundation

/// Zed: writes the palette as `~/.config/zed/themes/vibeshed.json` and selects it in
/// `settings.json` (settings apply live). If `theme` is a `{mode, light, dark}` object,
/// both variants are pointed at Vibeshed so the mode setting is kept.
/// `apps: { zed: "<theme name>" }` selects an installed theme instead.
struct ZedTarget: ThemeTarget {
    let id = ThemeTargetID.zed
    let displayName = "Zed"
    var supportsPreview: Bool { true }

    static let themeName = "Vibeshed"

    private static var configDir: String {
        ThemeFiles.home.appendingPathComponent(".config/zed").path
    }

    private static var settingsPath: String { "\(configDir)/settings.json" }
    private static var themePath: String { "\(configDir)/themes/vibeshed.json" }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        guard ThemeFiles.exists(Self.configDir) || ThemeApps.isInstalled("dev.zed.Zed") else {
            return .skipped("not installed")
        }
        do {
            let name: String
            if let override = request.override(.zed) {
                name = override
            } else {
                let family = ZedThemeBuilder.family(request.palette, name: Self.themeName)
                try ThemeFiles.writeJSON(family, to: Self.themePath)
                name = Self.themeName
            }
            var settings = JSONCDocument(text: ThemeFiles.read(Self.settingsPath))
            if var modal = settings.value(forKey: "theme") as? [String: Any] {
                modal["light"] = name
                modal["dark"] = name
                try settings.setValue(modal, forKey: "theme")
            } else {
                try settings.setValue(name, forKey: "theme")
            }
            try ThemeFiles.write(settings.text, to: Self.settingsPath)
            return .applied()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        ThemeFiles.snapshot([Self.settingsPath, Self.themePath])
    }
}

/// Builds a Zed theme family (schema v0.2.0) from a palette.
enum ZedThemeBuilder {
    static func family(_ palette: ThemePalette, name: String) -> [String: Any] {
        [
            "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
            "name": name,
            "author": "Vibeshed",
            "themes": [[
                "name": name,
                "appearance": palette.mode.rawValue,
                "style": style(palette),
            ]],
        ]
    }

    private static func style(_ palette: ThemePalette) -> [String: Any] {
        var style: [String: Any] = uiColors(palette).merging(statusColors(palette)) { $1 }
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        for (index, color) in palette.ansi.enumerated() {
            style["terminal.ansi.\(index >= 8 ? "bright_" : "")\(names[index % 8])"] = color.hex
        }
        style["players"] = [[
            "cursor": palette.cursor.hex,
            "background": palette.accent.hex,
            "selection": palette.selectionBackground.hex + "cc",
        ]]
        style["syntax"] = syntax(palette)
        return style
    }

    private static func uiColors(_ palette: ThemePalette) -> [String: Any] {
        let bg = palette.background.hex
        let surface = palette.darkBackground.hex
        let raised = palette.lighterBackground.hex
        let border = palette.background.mix(palette.foreground, 0.12).hex
        let muted = palette.muted.hex
        let accent = palette.accent.hex
        let selection = palette.selectionBackground.hex
        return [
            "background": surface, "surface.background": surface, "elevated_surface.background": raised,
            "panel.background": surface, "status_bar.background": surface, "title_bar.background": surface,
            "title_bar.inactive_background": surface, "toolbar.background": bg, "tab_bar.background": surface,
            "tab.inactive_background": surface, "tab.active_background": bg,
            "editor.background": bg, "editor.gutter.background": bg, "editor.subheader.background": surface,
            "editor.foreground": palette.foreground.hex, "editor.active_line.background": raised + "80",
            "editor.line_number": muted, "editor.active_line_number": palette.foreground.hex,
            "editor.invisible": border, "editor.wrap_guide": border, "editor.active_wrap_guide": muted,
            "editor.document_highlight.read_background": selection + "80",
            "editor.document_highlight.write_background": selection + "80",
            "border": border, "border.variant": border, "border.focused": accent, "border.selected": accent,
            "border.transparent": "#00000000", "border.disabled": border,
            "element.background": raised, "element.hover": selection + "80", "element.active": selection,
            "element.selected": selection, "element.disabled": surface,
            "ghost_element.background": "#00000000", "ghost_element.hover": selection + "80",
            "ghost_element.active": selection, "ghost_element.selected": selection,
            "drop_target.background": accent + "40", "search.match_background": accent + "50",
            "text": palette.foreground.hex, "text.muted": muted, "text.placeholder": muted,
            "text.disabled": muted, "text.accent": accent, "icon": palette.foreground.hex,
            "icon.muted": muted, "icon.disabled": muted, "icon.placeholder": muted, "icon.accent": accent,
            "link_text.hover": accent, "pane.focused_border": accent, "panel.focused_border": accent,
            "scrollbar.thumb.background": muted + "60", "scrollbar.thumb.hover_background": muted + "90",
            "scrollbar.thumb.border": "#00000000", "scrollbar.track.background": "#00000000",
            "scrollbar.track.border": "#00000000",
            "terminal.background": bg, "terminal.foreground": palette.foreground.hex,
            "terminal.bright_foreground": palette.brightForeground.hex, "terminal.dim_foreground": muted,
        ]
    }

    private static func statusColors(_ palette: ThemePalette) -> [String: Any] {
        let statuses: [(String, ThemeColor)] = [
            ("error", palette.red), ("deleted", palette.red), ("warning", palette.yellow),
            ("modified", palette.yellow), ("created", palette.green), ("success", palette.green),
            ("info", palette.blue), ("hint", palette.cyan), ("renamed", palette.blue),
            ("conflict", palette.orange), ("ignored", palette.muted), ("hidden", palette.muted),
            ("predictive", palette.muted), ("unreachable", palette.muted),
        ]
        var colors: [String: Any] = [:]
        for (name, color) in statuses {
            colors[name] = color.hex
            colors["\(name).background"] = palette.background.mix(color, 0.15).hex
            colors["\(name).border"] = palette.background.mix(color, 0.4).hex
        }
        return colors
    }

    private static func syntax(_ palette: ThemePalette) -> [String: Any] {
        let roles: [(String, String, String?)] = [
            ("attribute", "yellow", nil), ("boolean", "orange", nil), ("comment", "muted", "italic"),
            ("comment.doc", "muted", "italic"), ("constant", "orange", nil), ("constructor", "yellow", nil),
            ("embedded", "foreground", nil), ("emphasis", "magenta", "italic"),
            ("emphasis.strong", "orange", nil), ("enum", "yellow", nil), ("function", "blue", nil),
            ("keyword", "bright_magenta", nil), ("label", "cyan", nil), ("link_text", "blue", nil),
            ("link_uri", "cyan", nil), ("number", "orange", nil), ("operator", "bright_blue", nil),
            ("preproc", "magenta", nil), ("property", "cyan", nil), ("punctuation", "muted", nil),
            ("punctuation.bracket", "foreground", nil), ("punctuation.delimiter", "muted", nil),
            ("punctuation.special", "bright_magenta", nil), ("string", "green", nil),
            ("string.escape", "bright_cyan", nil), ("string.regex", "bright_cyan", nil),
            ("string.special", "cyan", nil), ("tag", "red", nil), ("text.literal", "green", nil),
            ("title", "accent", nil), ("type", "yellow", nil), ("variable", "foreground", nil),
            ("variable.special", "red", nil), ("variant", "orange", nil),
        ]
        var syntax: [String: Any] = [:]
        for (role, key, style) in roles {
            var entry: [String: Any] = ["color": palette[key]?.hex ?? palette.foreground.hex]
            if let style { entry["font_style"] = style }
            if role == "emphasis.strong" || role == "title" { entry["font_weight"] = 700 }
            syntax[role] = entry
        }
        return syntax
    }
}
