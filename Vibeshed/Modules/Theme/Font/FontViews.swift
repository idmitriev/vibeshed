import AppKit
import SwiftUI

/// Preview-panel content for a font: an editor and a terminal set in it, in the colors
/// of the theme on display, and the glyphs coding fonts are told apart by.
struct FontPreviewView: View {
    let font: ResolvedFont

    var body: some View {
        let palette = ActiveTheme.shared.displayed?.palette ?? Self.fallbackPalette
        PreviewLayout(moduleName: "theme") {
            VStack(alignment: .leading, spacing: 4) {
                Text(font.name)
                    .font(.face(font.editorFamily, size: 20))
                Text(font.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            FontSample(font: font, palette: palette)

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("Glyphs")
                Text("0O 1lI| {[()]} => != <= >= -> === ::")
                    .font(.face(font.editorFamily, size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            VStack(alignment: .leading, spacing: 4) {
                familyRow("Editors", font.editorFamily)
                familyRow("Terminals", font.terminalFamily + (font.hasIcons ? " · with icons" : ""))
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func familyRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            sectionLabel(label)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private static var fallbackPalette: ThemePalette {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = dark ? BuiltInThemes.oneDark : BuiltInThemes.catppuccinLatte
        return (try? ThemePalette.resolve(theme.colors, mode: theme.mode)) ?? ThemePalette(mode: .dark, colors: [:])
    }
}

/// A code window in the editor family over a terminal prompt in the terminal family.
private struct FontSample: View {
    let font: ResolvedFont
    let palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                codeLine(1, [("func ", palette.magenta), ("greet", palette.blue), ("(_ name: ", palette.foreground),
                             ("String", palette.yellow), (") -> ", palette.foreground), ("String", palette.yellow),
                             (" {", palette.foreground)])
                codeLine(2, [("    // => != <= >= ===", palette.muted)])
                codeLine(3, [("    guard ", palette.magenta), ("!name.isEmpty ", palette.foreground),
                             ("else ", palette.magenta), ("{ ", palette.foreground), ("return ", palette.magenta),
                             ("\"Hi!\"", palette.green), (" }", palette.foreground)])
                codeLine(4, [("    return ", palette.magenta), ("\"Hello, \\(name)\"", palette.green)])
                codeLine(5, [("}", palette.foreground)])
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.background.color)

            prompt
                .font(.face(font.terminalFamily, size: 12))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .background(palette.darkBackground.color)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.foreground.color.opacity(0.12), lineWidth: 1)
        )
    }

    /// Icon glyphs (Nerd Fonts' folder and Powerline's branch) only where the family has them.
    private var prompt: some View {
        HStack(spacing: 0) {
            Text(font.hasIcons ? "\u{F07C} ~/vibeshed " : "~/vibeshed ").foregroundStyle(palette.cyan.color)
            Text(font.hasIcons ? "\u{E0A0} main " : "main ").foregroundStyle(palette.magenta.color)
            Text("❯ ").foregroundStyle(palette.green.color)
            Text("ls -la").foregroundStyle(palette.foreground.color)
            Rectangle().fill(palette.cursor.color).frame(width: 7, height: 14)
        }
    }

    private func codeLine(_ number: Int, _ segments: [(String, ThemeColor)]) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .foregroundStyle(palette.muted.color)
                .frame(width: 14, alignment: .trailing)
            segments.reduce(Text("")) { text, segment in
                text + Text(segment.0).foregroundColor(segment.1.color)
            }
        }
        .font(.face(font.editorFamily, size: 12))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Font {
    /// The regular face of an installed family; the system monospace when it has none.
    static func face(_ family: String, size: CGFloat) -> Font {
        guard let name = FontFaces.face(of: family, like: nil) else { return .system(size: size, design: .monospaced) }
        return .custom(name, fixedSize: size)
    }
}
