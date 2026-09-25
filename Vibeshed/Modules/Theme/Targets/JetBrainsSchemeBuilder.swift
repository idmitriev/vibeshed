import Foundation

/// Builds a JetBrains editor color scheme (`.icls`) from a palette, inheriting everything
/// it doesn't set from Darcula (dark) or Default (light).
enum JetBrainsSchemeBuilder {
    static func scheme(_ palette: ThemePalette, id: String, fontOptions: [String]) -> String {
        let parent = palette.mode == .dark ? "Darcula" : "Default"
        let fonts = fontOptions.map { "  \($0)" }.joined(separator: "\n")
        let colorLines = colors(palette).map { name, color in
            "    <option name=\"\(name)\" value=\"\(color.hexStripped)\" />"
        }
        return """
        <scheme name="\(id)" version="142" parent_scheme="\(parent)">
          <metaInfo>
            <property name="ide">idea</property>
            <property name="originalScheme">Vibeshed</property>
          </metaInfo>
        \(fonts)
          <colors>
        \(colorLines.joined(separator: "\n"))
          </colors>
          <attributes>
        \(attributes(palette).joined(separator: "\n"))
          </attributes>
        </scheme>

        """
    }

    private static func colors(_ palette: ThemePalette) -> [(String, ThemeColor)] {
        let border = palette.background.mix(palette.foreground, 0.12)
        return [
            ("CARET_COLOR", palette.cursor),
            ("CARET_ROW_COLOR", palette.lighterBackground),
            ("SELECTION_BACKGROUND", palette.selectionBackground),
            ("SELECTION_FOREGROUND", palette.selectionForeground),
            ("LINE_NUMBERS_COLOR", palette.muted),
            ("LINE_NUMBER_ON_CARET_ROW_COLOR", palette.foreground),
            ("GUTTER_BACKGROUND", palette.background),
            ("INDENT_GUIDE", border),
            ("SELECTED_INDENT_GUIDE", palette.muted),
            ("RIGHT_MARGIN_COLOR", border),
            ("TEARLINE_COLOR", border),
            ("WHITESPACES", border),
            ("CONSOLE_BACKGROUND_KEY", palette.background),
            ("DOCUMENTATION_COLOR", palette.darkBackground),
            ("NOTIFICATION_BACKGROUND", palette.lighterBackground),
            ("ADDED_LINES_COLOR", palette.green),
            ("MODIFIED_LINES_COLOR", palette.blue),
            ("DELETED_LINES_COLOR", palette.red),
        ]
    }

    private static func attributes(_ palette: ThemePalette) -> [String] {
        let color = { (key: String) in palette[key] ?? palette.foreground }
        // (attribute, palette key, font type: 1 bold, 2 italic)
        let syntax: [(String, String, Int?)] = [
            ("DEFAULT_KEYWORD", "bright_magenta", nil), ("DEFAULT_STRING", "green", nil),
            ("DEFAULT_VALID_STRING_ESCAPE", "bright_cyan", nil), ("DEFAULT_NUMBER", "orange", nil),
            ("DEFAULT_CONSTANT", "orange", nil), ("DEFAULT_LINE_COMMENT", "muted", 2),
            ("DEFAULT_BLOCK_COMMENT", "muted", 2), ("DEFAULT_DOC_COMMENT", "muted", 2),
            ("DEFAULT_FUNCTION_DECLARATION", "blue", nil), ("DEFAULT_FUNCTION_CALL", "blue", nil),
            ("DEFAULT_INSTANCE_METHOD", "blue", nil), ("DEFAULT_STATIC_METHOD", "blue", nil),
            ("DEFAULT_CLASS_NAME", "yellow", nil), ("DEFAULT_INTERFACE_NAME", "yellow", nil),
            ("DEFAULT_CLASS_REFERENCE", "yellow", nil), ("DEFAULT_PARAMETER", "cyan", nil),
            ("DEFAULT_INSTANCE_FIELD", "cyan", nil), ("DEFAULT_STATIC_FIELD", "cyan", nil),
            ("DEFAULT_IDENTIFIER", "foreground", nil), ("DEFAULT_LOCAL_VARIABLE", "foreground", nil),
            ("DEFAULT_OPERATION_SIGN", "bright_blue", nil), ("DEFAULT_METADATA", "blue", nil),
            ("DEFAULT_PREDEFINED_SYMBOL", "cyan", nil), ("DEFAULT_LABEL", "cyan", nil),
            ("DEFAULT_TAG", "red", nil), ("DEFAULT_ATTRIBUTE", "yellow", nil),
            ("DEFAULT_ENTITY", "orange", nil),
        ]
        var lines = [option("TEXT", foreground: palette.foreground, background: palette.background)]
        lines += syntax.map { option($0.0, foreground: color($0.1), fontType: $0.2) }

        let consoleNames = ["BLACK", "RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN", "GRAY",
                            "DARKGRAY", "RED_BRIGHT", "GREEN_BRIGHT", "YELLOW_BRIGHT", "BLUE_BRIGHT",
                            "MAGENTA_BRIGHT", "CYAN_BRIGHT", "WHITE"]
        for (name, ansi) in zip(consoleNames, palette.ansi) {
            lines.append(option("CONSOLE_\(name)_OUTPUT", foreground: ansi))
        }
        lines.append(option("CONSOLE_NORMAL_OUTPUT", foreground: palette.foreground))
        lines.append(option("CONSOLE_ERROR_OUTPUT", foreground: palette.red))
        lines.append(option("CONSOLE_SYSTEM_OUTPUT", foreground: palette.muted))
        return lines
    }

    private static func option(
        _ name: String,
        foreground: ThemeColor,
        background: ThemeColor? = nil,
        fontType: Int? = nil
    ) -> String {
        var values = ["        <option name=\"FOREGROUND\" value=\"\(foreground.hexStripped)\" />"]
        if let background {
            values.append("        <option name=\"BACKGROUND\" value=\"\(background.hexStripped)\" />")
        }
        if let fontType {
            values.append("        <option name=\"FONT_TYPE\" value=\"\(fontType)\" />")
        }
        return """
            <option name="\(name)">
              <value>
        \(values.joined(separator: "\n"))
              </value>
            </option>
        """
    }
}
