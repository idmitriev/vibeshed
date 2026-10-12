import Foundation
import SwiftUI

/// Coding fonts: `theme/switchFont` browses the installed ones with live preview and sets
/// the chosen font in terminals and editors (see `FontApplier.targets`); every font is
/// also a direct action, `theme/font.<slug>`.
extension ThemeModule {
    static let switchFontActionID = ActionID(module: "theme", name: "switchFont")

    /// Installed fonts, rescanned each time, so a font installed meanwhile shows up.
    func fonts() -> [ResolvedFont] {
        guard !FontApplier.enabledTargets(config: config).isEmpty else { return [] }
        return FontCatalog.fonts(config: config)
    }

    /// The font in use, so the list opens on it rather than previewing another one.
    private func currentFont(among fonts: [ResolvedFont]) -> String? {
        FontCatalog.current(among: fonts, targets: FontApplier.enabledTargets(config: config), config: config)?.slug
    }

    func fontActions() -> [ThemeAction] {
        let fonts = fonts()
        guard !fonts.isEmpty else { return [] }
        let current = currentFont(among: fonts)
        return [switchFontAction()] + fonts.map { fontAction($0, isCurrent: $0.slug == current) }
    }

    func fontOptions() -> [ParameterOption] {
        let fonts = fonts()
        let current = currentFont(among: fonts)
        return fonts.map { font in
            ParameterOption(
                id: font.slug,
                label: font.name,
                subtitle: Self.describe(font),
                iconName: "textformat",
                keywords: font.keywords + [font.editorFamily, font.terminalFamily],
                isCurrent: font.slug == current,
                makePreview: { AnyView(FontPreviewView(font: font)) }
            )
        }
    }

    func previewFont(_ slug: String) async {
        let fonts = fonts()
        guard let font = fonts.first(where: { $0.slug == slug }) else { return }
        await fontApplier.preview(font, config: config, isCurrent: font.slug == currentFont(among: fonts))
    }

    private func applyFont(slug: String) async -> ActionResult {
        guard let font = fonts().first(where: { $0.slug == slug }) else {
            return .showResult(title: "Font", body: "No installed font named '\(slug)'")
        }
        let failures = await fontApplier.apply(font, config: config).compactMap { result -> String? in
            if case let .failed(reason) = result.outcome { return "\(result.target): \(reason)" }
            return nil
        }
        guard !failures.isEmpty else { return .dismiss }
        return .showResult(title: "\(font.name) applied with errors", body: failures.joined(separator: "\n"))
    }

    static func describe(_ font: ResolvedFont) -> String {
        font.hasIcons ? "\(font.summary) · icons in terminals" : font.summary
    }

    private func switchFontAction() -> ThemeAction {
        ThemeAction(
            id: Self.switchFontActionID,
            title: "Switch Font…",
            subtitle: "Browse coding fonts for terminals and editors — each previews live; Return applies, Esc reverts",
            iconName: "textformat",
            relevanceScore: 0.85,
            keywords: ["font", "typeface", "monospace", "coding", "terminal", "editor", "switch"],
            parameters: [
                ActionParameter(
                    id: "font", label: "Font", type: .dynamicSelection(hint: "font"),
                    isRequired: true, livePreview: true
                ),
            ]
        ) { values in
            guard let slug = values["font"] else { return .keepOpen }
            return await self.applyFont(slug: slug)
        }
    }

    private func fontAction(_ font: ResolvedFont, isCurrent: Bool) -> ThemeAction {
        let words = font.name.lowercased().split(separator: " ").map(String.init)
        return ThemeAction(
            id: ActionID(module: "theme", name: "font.\(font.slug)"),
            title: font.name,
            subtitle: (isCurrent ? "Current font · " : "Font · ") + Self.describe(font),
            iconName: "textformat",
            relevanceScore: 0.6,
            keywords: ["font", "typeface"] + words + font.keywords,
            font: font
        ) { _ in
            await self.applyFont(slug: font.slug)
        }
    }
}
