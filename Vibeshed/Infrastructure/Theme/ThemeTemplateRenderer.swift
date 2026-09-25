import Foundation

/// Renders theme templates. The placeholder language is Omarchy's (`default/themed/*.tpl`),
/// so its templates work as-is:
///
/// - `{{ key }}` → `#rrggbb` (or the raw string for `mode`, `theme_type`, `theme_name`)
/// - `{{ key_strip }}` → `rrggbb`, `{{ key_rgb }}` → `r,g,b`
/// - `{{ mix a b 30% }}` → `a` blended 30% toward `b` (also `mix_strip`, `mix_rgb`)
///
/// Aether-style dot modifiers (`{{ key.hex }}`, `{{ key.strip }}`, `{{ key.rgb }}`) are
/// accepted too. Unknown placeholders are left untouched and reported.
enum ThemeTemplateRenderer {
    struct Output: Equatable {
        let text: String
        /// Placeholder bodies that didn't resolve, in first-seen order.
        let unresolved: [String]
    }

    static func render(_ template: String, palette: ThemePalette, themeName: String) -> Output {
        var strings = palette.templateVariables
        strings["theme_name"] = themeName

        var unresolved: [String] = []
        var result = ""
        var cursor = template.startIndex

        while let open = template.range(of: "{{", range: cursor ..< template.endIndex),
              let close = template.range(of: "}}", range: open.upperBound ..< template.endIndex)
        {
            result += template[cursor ..< open.lowerBound]
            let body = template[open.upperBound ..< close.lowerBound].trimmingCharacters(in: .whitespaces)
            if let value = resolve(body, palette: palette, strings: strings) {
                result += value
            } else {
                result += template[open.lowerBound ..< close.upperBound]
                if !unresolved.contains(body) { unresolved.append(body) }
            }
            cursor = close.upperBound
        }
        result += template[cursor...]
        return Output(text: result, unresolved: unresolved)
    }

    private enum Format {
        case hex, strip, rgb

        func apply(_ color: ThemeColor) -> String {
            switch self {
            case .hex: color.hex
            case .strip: color.hexStripped
            case .rgb: color.rgbString
            }
        }
    }

    private static func resolve(_ body: String, palette: ThemePalette, strings: [String: String]) -> String? {
        let parts = body.split(whereSeparator: \.isWhitespace).map(String.init)
        if parts.count == 4, let format = mixFormat(parts[0]) {
            guard let from = palette[parts[1]], let to = palette[parts[2]],
                  let amount = parseAmount(parts[3])
            else { return nil }
            return format.apply(from.mix(to, amount))
        }
        guard parts.count == 1 else { return nil }
        let key = parts[0]

        if let color = palette[key] { return color.hex }
        if let string = strings[key] { return string }

        for (suffix, format) in [("_strip", Format.strip), ("_rgb", .rgb), (".strip", .strip),
                                 (".rgb", .rgb), (".hex", .hex)] where key.hasSuffix(suffix)
        {
            if let color = palette[String(key.dropLast(suffix.count))] {
                return format.apply(color)
            }
        }
        return nil
    }

    private static func mixFormat(_ name: String) -> Format? {
        switch name {
        case "mix": .hex
        case "mix_strip": .strip
        case "mix_rgb": .rgb
        default: nil
        }
    }

    /// `30%`, `0.3` and `30` all mean 30% (Omarchy treats bare numbers > 1 as percentages).
    private static func parseAmount(_ string: String) -> Double? {
        if string.hasSuffix("%") {
            return Double(string.dropLast()).map { $0 / 100 }
        }
        guard let value = Double(string) else { return nil }
        return value > 1 ? value / 100 : value
    }
}
