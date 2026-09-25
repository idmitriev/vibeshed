import Foundation

/// Builds a VS Code color theme (`vscode://schemas/color-theme`) from a palette.
/// Token roles follow Omarchy's `vscode-theme.json.tpl`, so a palette looks the same
/// here as it does in an Omarchy setup.
enum VSCodeThemeBuilder {
    static func theme(_ palette: ThemePalette, name: String) -> [String: Any] {
        [
            "name": name,
            "$schema": "vscode://schemas/color-theme",
            "type": palette.mode.rawValue,
            "semanticHighlighting": true,
            "colors": workbenchColors(palette),
            "semanticTokenColors": semanticTokens(palette),
            "tokenColors": tokenColors(palette),
        ]
    }

    // MARK: - Workbench

    /// Shared tones for the workbench sections.
    private struct Tones {
        let bg, sidebar, surface, fg, muted, accent, onAccent, border, selection: String

        init(_ palette: ThemePalette) {
            bg = palette.background.hex
            sidebar = palette.darkBackground.hex
            surface = palette.lighterBackground.hex
            fg = palette.foreground.hex
            muted = palette.muted.hex
            accent = palette.accent.hex
            onAccent = palette.accent.contrastingText.hex
            border = palette.background.mix(palette.foreground, 0.12).hex
            selection = palette.selectionBackground.hex
        }
    }

    private static func workbenchColors(_ palette: ThemePalette) -> [String: String] {
        let tones = Tones(palette)
        var colors = baseColors(palette, tones)
            .merging(editorColors(palette, tones)) { $1 }
            .merging(chromeColors(palette, tones)) { $1 }
            .merging(controlColors(palette, tones)) { $1 }
        let ansiNames = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        for (index, color) in palette.ansi.enumerated() {
            colors["terminal.ansi\(index >= 8 ? "Bright" : "")\(ansiNames[index % 8])"] = color.hex
        }
        return colors
    }

    private static func baseColors(_ palette: ThemePalette, _ tones: Tones) -> [String: String] {
        [
            "foreground": tones.fg, "descriptionForeground": tones.muted, "errorForeground": palette.red.hex,
            "focusBorder": tones.accent + "80", "icon.foreground": tones.fg,
            "widget.shadow": palette.darkerBackground.hex + "80", "selection.background": tones.selection + "80",
            "textLink.foreground": palette.blue.hex,
            "textLink.activeForeground": palette["bright_blue"]?.hex ?? palette.blue.hex,
            "textPreformat.foreground": palette.cyan.hex, "textBlockQuote.border": tones.accent,
            "gitDecoration.addedResourceForeground": palette.green.hex,
            "gitDecoration.modifiedResourceForeground": palette.blue.hex,
            "gitDecoration.deletedResourceForeground": palette.red.hex,
            "gitDecoration.untrackedResourceForeground": palette.cyan.hex,
            "gitDecoration.ignoredResourceForeground": tones.muted,
            "terminal.background": tones.bg, "terminal.foreground": tones.fg,
            "terminalCursor.foreground": palette.cursor.hex, "terminal.selectionBackground": tones.selection,
        ]
    }

    private static func editorColors(_ palette: ThemePalette, _ tones: Tones) -> [String: String] {
        [
            "editor.background": tones.bg, "editor.foreground": tones.fg,
            "editor.lineHighlightBackground": tones.surface + "80",
            "editor.selectionBackground": tones.selection,
            "editor.inactiveSelectionBackground": tones.selection + "80",
            "editor.selectionHighlightBackground": tones.selection + "60",
            "editor.wordHighlightBackground": tones.selection + "60",
            "editor.findMatchBackground": tones.accent + "50",
            "editor.findMatchHighlightBackground": tones.accent + "30",
            "editorCursor.foreground": palette.cursor.hex, "editorLineNumber.foreground": tones.muted,
            "editorLineNumber.activeForeground": tones.fg, "editorIndentGuide.background1": tones.border,
            "editorIndentGuide.activeBackground1": tones.muted, "editorWhitespace.foreground": tones.border,
            "editorBracketMatch.background": tones.selection + "80", "editorBracketMatch.border": tones.accent,
            "editorError.foreground": palette.red.hex, "editorWarning.foreground": palette.yellow.hex,
            "editorInfo.foreground": palette.blue.hex, "editorHint.foreground": palette.cyan.hex,
            "editorGutter.addedBackground": palette.green.hex,
            "editorGutter.modifiedBackground": palette.blue.hex,
            "editorGutter.deletedBackground": palette.red.hex,
            "editorWidget.background": tones.sidebar, "editorWidget.border": tones.border,
            "editorSuggestWidget.background": tones.sidebar,
            "editorSuggestWidget.selectedBackground": tones.selection,
            "editorHoverWidget.background": tones.sidebar, "editorHoverWidget.border": tones.border,
            "editorGroupHeader.tabsBackground": tones.sidebar, "editorGroup.border": tones.border,
            "peekView.border": tones.accent, "peekViewEditor.background": tones.sidebar,
            "peekViewResult.background": tones.sidebar,
        ]
    }

    private static func chromeColors(_ palette: ThemePalette, _ tones: Tones) -> [String: String] {
        [
            "activityBar.background": tones.sidebar, "activityBar.foreground": tones.fg,
            "activityBar.inactiveForeground": tones.muted, "activityBar.border": tones.border,
            "activityBarBadge.background": tones.accent, "activityBarBadge.foreground": tones.onAccent,
            "activityBar.activeBorder": tones.accent,
            "sideBar.background": tones.sidebar, "sideBar.foreground": tones.fg, "sideBar.border": tones.border,
            "sideBarTitle.foreground": tones.fg, "sideBarSectionHeader.background": tones.sidebar,
            "tab.activeBackground": tones.bg, "tab.inactiveBackground": tones.sidebar,
            "tab.activeForeground": tones.fg, "tab.inactiveForeground": tones.muted,
            "tab.border": tones.border, "tab.activeBorderTop": tones.accent,
            "titleBar.activeBackground": tones.sidebar, "titleBar.activeForeground": tones.fg,
            "titleBar.inactiveBackground": tones.sidebar, "titleBar.inactiveForeground": tones.muted,
            "titleBar.border": tones.border,
            "statusBar.background": tones.sidebar, "statusBar.foreground": tones.fg,
            "statusBar.border": tones.border, "statusBar.debuggingBackground": palette.orange.hex,
            "statusBarItem.remoteBackground": tones.accent, "statusBarItem.remoteForeground": tones.onAccent,
            "panel.background": tones.sidebar, "panel.border": tones.border,
            "panelTitle.activeBorder": tones.accent, "panelTitle.activeForeground": tones.fg,
            "panelTitle.inactiveForeground": tones.muted,
        ]
    }

    private static func controlColors(_ palette: ThemePalette, _ tones: Tones) -> [String: String] {
        [
            "list.activeSelectionBackground": tones.selection, "list.activeSelectionForeground": tones.fg,
            "list.inactiveSelectionBackground": tones.selection + "80", "list.hoverBackground": tones.surface,
            "list.focusOutline": tones.accent + "80", "list.highlightForeground": tones.accent,
            "input.background": tones.surface, "input.foreground": tones.fg, "input.border": tones.border,
            "input.placeholderForeground": tones.muted, "dropdown.background": tones.surface,
            "dropdown.border": tones.border,
            "button.background": tones.accent, "button.foreground": tones.onAccent,
            "button.hoverBackground": palette.accent.mix(palette.foreground, 0.15).hex,
            "badge.background": tones.accent, "badge.foreground": tones.onAccent,
            "progressBar.background": tones.accent, "scrollbarSlider.background": tones.muted + "40",
            "scrollbarSlider.hoverBackground": tones.muted + "60",
            "scrollbarSlider.activeBackground": tones.muted + "80",
            "quickInput.background": tones.sidebar, "quickInputList.focusBackground": tones.selection,
        ]
    }

    // MARK: - Syntax

    private static func semanticTokens(_ palette: ThemePalette) -> [String: Any] {
        let hex = { (key: String) in palette[key]?.hex ?? palette.foreground.hex }
        return [
            "parameter": hex("cyan"), "variable": hex("foreground"), "variable.readonly": hex("bright_yellow"),
            "property": hex("cyan"), "function": hex("blue"), "method": hex("blue"),
            "function.defaultLibrary": hex("cyan"), "class": hex("yellow"), "interface": hex("yellow"),
            "enum": hex("yellow"), "enumMember": hex("orange"), "type": hex("yellow"),
            "typeParameter": hex("yellow"), "namespace": hex("blue"), "macro": hex("cyan"),
            "decorator": hex("blue"), "string": hex("green"), "number": hex("orange"),
            "boolean": hex("orange"), "regexp": hex("bright_cyan"), "operator": hex("bright_blue"),
            "keyword": hex("bright_magenta"),
            "comment": ["foreground": hex("muted"), "fontStyle": "italic"],
        ]
    }

    /// TextMate scope rules; also reused for the bat `.tmTheme`.
    static func tokenColors(_ palette: ThemePalette) -> [[String: Any]] {
        let hex = { (key: String) in palette[key]?.hex ?? palette.foreground.hex }
        func rule(_ scopes: [String], _ key: String, style: String? = nil) -> [String: Any] {
            var settings: [String: String] = ["foreground": hex(key)]
            if let style { settings["fontStyle"] = style }
            return ["scope": scopes, "settings": settings]
        }
        return [
            rule(["comment", "punctuation.definition.comment"], "muted", style: "italic"),
            rule(["string", "string.quoted", "string.template"], "green"),
            rule(["constant.character.escape", "string.regexp"], "bright_cyan"),
            rule(["constant.numeric", "constant.language", "constant.language.boolean"], "orange"),
            rule(["keyword", "storage", "storage.type", "storage.modifier"], "bright_magenta"),
            rule(["keyword.operator", "punctuation.accessor"], "bright_blue"),
            rule(["entity.name.function", "support.function", "meta.function-call"], "blue"),
            rule(["entity.name.type", "entity.name.class", "support.type", "support.class"], "yellow"),
            rule(["variable.parameter"], "cyan"),
            rule(["variable.other.property", "support.variable.property", "meta.property-name"], "cyan"),
            rule(["variable", "variable.other"], "foreground"),
            rule(["entity.name.tag"], "red"),
            rule(["entity.other.attribute-name"], "yellow", style: "italic"),
            rule(["meta.decorator", "entity.name.function.decorator"], "blue"),
            rule(["markup.heading", "entity.name.section"], "accent", style: "bold"),
            rule(["markup.bold"], "orange", style: "bold"),
            rule(["markup.italic"], "magenta", style: "italic"),
            rule(["markup.inline.raw", "markup.fenced_code"], "cyan"),
            rule(["markup.underline.link"], "blue"),
            rule(["markup.inserted"], "green"),
            rule(["markup.deleted"], "red"),
            rule(["markup.changed"], "yellow"),
            rule(["invalid"], "red"),
        ]
    }
}
