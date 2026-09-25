import AppKit
import Foundation
import OSLog
import SwiftUI

/// Palette themes applied across macOS and apps (see `ThemeApplier.targets`), browsed
/// with live preview in `theme/switch`.
actor ThemeModule: ModuleConfigurable {
    let id = "theme"
    let displayName = "Theme"
    let iconName = "paintpalette"
    var isEnabled = true

    typealias Config = ThemeConfig
    static var defaultConfig: Config? {
        .init()
    }

    static let switchActionID = ActionID(module: "theme", name: "switch")
    private static let generatedDefaultsKey = "theme.generated"

    // Internal (not private) for the wallpaper actions in ThemeModule+Wallpaper.
    private(set) var config = ThemeConfig()
    private(set) var catalog = ThemeCatalog.Result(themes: [], errors: [])
    private(set) var eventBus: EventBus?
    let applier = ThemeApplier()
    private let log = Log.module("theme")
    private var itermWatcher: AppLaunchWatcher?

    func initialize(context: ModuleContext) async throws {
        eventBus = context.eventBus
        rebuildCatalog()
        itermWatcher = await MainActor.run {
            AppLaunchWatcher(bundleID: ITermTarget.bundleID) { [weak self] in
                Task { await self?.recolorLaunchedITerm() }
            }
        }
    }

    func teardown() async {
        await itermWatcher?.stop()
    }

    /// Windows iTerm restores keep the profile they were created with, so recolor
    /// every session once iTerm has launched (new ones use the Vibeshed default profile).
    private func recolorLaunchedITerm() async {
        guard config.enabledTargets.contains(.iterm), let theme = await currentTheme() else { return }
        try? await Task.sleep(for: .seconds(2.5))
        let options = ThemeApplier.Options(wallpaper: wallpaperChoice(for: theme), only: [.iterm])
        _ = await applier.apply(theme, config: config, options: options)
    }

    func configDidUpdate(_ config: ThemeConfig) async {
        self.config = config
        rebuildCatalog()
        await eventBus?.publish(.moduleActionsChanged(moduleID: id))
    }

    static func validate(_ config: ThemeConfig) -> ConfigValidationResult {
        var errors: [String] = []
        let slugs = config.themes.map { ResolvedTheme.slug(for: $0.name) }
        if slugs.contains(where: \.isEmpty) { errors.append("Theme names cannot be empty") }
        if Set(slugs).count != slugs.count { errors.append("Theme names must be unique") }

        for theme in config.themes {
            for (key, value) in theme.colors where !ThemePalette.nonColorKeys.contains(key)
                && ThemeColor(hex: value) == nil
            {
                errors.append("Theme '\(theme.name)': '\(key)' is not a hex color: '\(value)'")
            }
            for app in theme.apps.keys where !ThemeAppOverride.keys.contains(app) {
                let known = ThemeAppOverride.keys.sorted().joined(separator: ", ")
                errors.append("Theme '\(theme.name)': unknown app '\(app)' (known: \(known))")
            }
            if let accent = theme.macosAccent, MacAccentColor.named(accent) == nil {
                let known = MacAccentColor.allCases.map(\.rawValue).joined(separator: ", ")
                errors.append("Theme '\(theme.name)': macosAccent must be one of \(known)")
            }
        }
        // Palette completeness (after `base` inheritance) for the themes config defines.
        let configNames = Set(config.themes.map(\.name))
        errors += ThemeCatalog.build(config: config, generated: nil).errors.filter { error in
            configNames.contains { error.hasPrefix("Theme '\($0)'") }
        }

        for target in config.targets ?? [] where ThemeTargetID(rawValue: target) == nil {
            let known = ThemeTargetID.allCases.map(\.rawValue).joined(separator: ", ")
            errors.append("Unknown target '\(target)' (known: \(known))")
        }
        for template in config.templates where template.source.isEmpty || template.target.isEmpty {
            errors.append("Templates need both source and target")
        }
        let styles = WallpaperStyle.allCases.map(\.rawValue).joined(separator: ", ")
        let styleNames = [("wallpaperStyle", config.wallpaperStyle)] + config.themes.compactMap { theme in
            theme.wallpaperStyle.map { ("Theme '\(theme.name)': wallpaperStyle", $0) }
        }
        for (label, name) in styleNames where WallpaperStyle.resolve(name, slug: "") == nil {
            errors.append("\(label) '\(name)' is not one of auto, \(styles)")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    // MARK: - Actions

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let current = await MainActor.run { ActiveTheme.shared.committed?.slug }
        var actions: [ThemeAction] = [switchAction(), fromWallpaperAction()]
        if !catalog.themes.isEmpty {
            actions += [cycleAction(forward: true), cycleAction(forward: false), reapplyAction()]
            actions += [wallpaperStyleAction(), shuffleWallpaperAction()]
        }
        actions += catalog.themes.map { applyAction($0, isCurrent: $0.slug == current) }

        guard let enabled = config.enabledActions else { return actions }
        return actions.filter { action in
            let name = action.id.actionName
            return enabled.contains(name) || enabled.contains(String(name.prefix { $0 != "." }))
        }
    }

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        if parameterID == "style" { return await wallpaperStyleOptions() }
        guard parameterID == "theme" else { return [] }
        let current = await MainActor.run { ActiveTheme.shared.committed?.slug }
        return catalog.themes.map { theme in
            let wallpaper = previewWallpaper(for: theme)
            return ParameterOption(
                id: theme.slug,
                label: theme.name,
                subtitle: Self.describe(theme),
                iconName: theme.icon,
                isCurrent: theme.slug == current,
                swatches: theme.palette.signature.dropFirst(2).prefix(6).map(\.color),
                makePreview: { AnyView(ThemePreviewView(theme: theme, wallpaper: wallpaper)) }
            )
        }
    }

    func previewParameterOption(_ optionID: String, parameterID: String, actionID: ActionID) async {
        guard config.livePreview else { return }
        if actionID == Self.wallpaperStyleActionID {
            return await previewWallpaperStyle(optionID)
        }
        guard actionID == Self.switchActionID, let theme = catalog.theme(slug: optionID) else { return }
        let current = await MainActor.run { ActiveTheme.shared.committed?.slug }
        let options = ThemeApplier.Options(wallpaper: wallpaperChoice(for: theme), only: nil)
        await applier.preview(theme, config: config, options: options, isCurrent: theme.slug == current)
    }

    func endParameterPreview(parameterID: String, actionID: ActionID, committed: Bool) async {
        guard actionID == Self.switchActionID || actionID == Self.wallpaperStyleActionID else { return }
        await applier.endPreview(committed: committed)
    }

    // MARK: - Applying

    private func apply(slug: String) async -> ActionResult {
        guard let theme = catalog.theme(slug: slug) else {
            return .showResult(title: "Theme", body: "No theme named '\(slug)'")
        }
        let options = ThemeApplier.Options(wallpaper: wallpaperChoice(for: theme), only: nil)
        return Self.summary(theme, await applier.apply(theme, config: config, options: options))
    }

    private func applyCycled(forward: Bool) async -> ActionResult {
        let current = await MainActor.run { ActiveTheme.shared.committed?.slug }
        let themes = catalog.themes
        guard !themes.isEmpty else { return .dismiss }
        let index = themes.firstIndex { $0.slug == current }
        let next = index.map { (themes.count + $0 + (forward ? 1 : -1)) % themes.count } ?? 0
        return await apply(slug: themes[next].slug)
    }

    private func generateFromWallpaper() async -> ActionResult {
        let generated = await MainActor.run { () -> (colors: [String: String], wallpaper: String?)? in
            guard let image = ThemeGenerator.currentWallpaperImage(),
                  let colors = ThemeGenerator.palette(from: image)
            else { return nil }
            let path = NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0)?.path }
            return (colors, path)
        }
        guard let generated else {
            return .showResult(title: "Theme", body: "Couldn't read the current wallpaper")
        }
        // Kept across launches, so the generated theme stays in the list.
        UserDefaults.standard.set(generated.colors, forKey: Self.generatedDefaultsKey)
        UserDefaults.standard.set(generated.wallpaper, forKey: Self.generatedDefaultsKey + ".wallpaper")
        rebuildCatalog()
        await eventBus?.publish(.moduleActionsChanged(moduleID: id))
        return await apply(slug: ResolvedTheme.slug(for: ThemeGenerator.generatedName))
    }

    private func rebuildCatalog() {
        catalog = ThemeCatalog.build(config: config, generated: storedGeneratedTheme())
        for error in catalog.errors {
            log.error("\(error, privacy: .public)")
        }
    }

    private func storedGeneratedTheme() -> ThemeDefinition? {
        guard let colors = UserDefaults.standard.dictionary(forKey: Self.generatedDefaultsKey) as? [String: String]
        else { return nil }
        return ThemeDefinition(
            name: ThemeGenerator.generatedName, colors: colors,
            wallpaper: UserDefaults.standard.string(forKey: Self.generatedDefaultsKey + ".wallpaper"),
            icon: "wand.and.stars", subtitle: "Generated from the current wallpaper",
            keywords: ["wallpaper", "generate", "aether"]
        )
    }

    /// Stay quiet on success — the desktop changing is the feedback. Surface failures.
    static func summary(_ theme: ResolvedTheme, _ results: [ThemeApplier.Result]) -> ActionResult {
        let failures = results.compactMap { result -> String? in
            if case let .failed(reason) = result.outcome { return "\(result.target): \(reason)" }
            return nil
        }
        guard !failures.isEmpty else { return .dismiss }
        return .showResult(title: "\(theme.name) applied with errors", body: failures.joined(separator: "\n"))
    }

    static func describe(_ theme: ResolvedTheme) -> String {
        if let subtitle = theme.subtitle { return subtitle }
        let mode = theme.palette.mode == .dark ? "Dark" : "Light"
        return theme.source == .builtIn ? "\(mode) theme" : "\(mode) theme · \(theme.source.rawValue)"
    }
}

// MARK: - Action builders

private extension ThemeModule {
    func switchAction() -> ThemeAction {
        ThemeAction(
            id: Self.switchActionID,
            title: "Switch Theme…",
            subtitle: "Browse themes — each one previews live as you move; Return applies, Esc reverts",
            iconName: "paintpalette.fill",
            relevanceScore: 0.9,
            keywords: ["theme", "palette", "colors", "appearance", "scheme", "dark", "light", "switch"],
            parameters: [
                ActionParameter(
                    id: "theme", label: "Theme", type: .dynamicSelection(hint: "theme"),
                    isRequired: true, livePreview: true
                ),
            ]
        ) { values in
            guard let slug = values["theme"] else { return .keepOpen }
            return await self.apply(slug: slug)
        }
    }

    func applyAction(_ theme: ResolvedTheme, isCurrent: Bool) -> ThemeAction {
        let words = theme.name.lowercased().split(separator: " ").map(String.init)
        return ThemeAction(
            id: ActionID(module: "theme", name: "apply.\(theme.slug)"),
            title: theme.name,
            subtitle: isCurrent ? "Current theme · \(Self.describe(theme))" : Self.describe(theme),
            iconName: theme.icon,
            relevanceScore: 0.8,
            keywords: ["theme", "palette", theme.palette.mode.rawValue] + words + theme.keywords,
            theme: theme,
            wallpaper: previewWallpaper(for: theme)
        ) { _ in
            await self.apply(slug: theme.slug)
        }
    }

    func cycleAction(forward: Bool) -> ThemeAction {
        ThemeAction(
            id: ActionID(module: "theme", name: forward ? "next" : "previous"),
            title: forward ? "Next Theme" : "Previous Theme",
            subtitle: "Apply the \(forward ? "next" : "previous") theme in the list",
            iconName: forward ? "arrow.right.circle" : "arrow.left.circle",
            relevanceScore: 0.7,
            keywords: ["theme", "cycle", forward ? "next" : "previous"]
        ) { _ in
            await self.applyCycled(forward: forward)
        }
    }

    func reapplyAction() -> ThemeAction {
        ThemeAction(
            id: ActionID(module: "theme", name: "reapply"),
            title: "Reapply Theme",
            subtitle: "Re-sync the current theme, e.g. after opening new terminal windows",
            iconName: "arrow.clockwise.circle",
            relevanceScore: 0.65,
            keywords: ["theme", "reapply", "refresh", "sync"]
        ) { _ in
            guard let slug = await MainActor.run(body: { ActiveTheme.shared.committed?.slug }) else {
                return .showResult(title: "Theme", body: "No theme applied yet")
            }
            return await self.apply(slug: slug)
        }
    }

    func fromWallpaperAction() -> ThemeAction {
        ThemeAction(
            id: ActionID(module: "theme", name: "fromWallpaper"),
            title: "Generate Theme from Wallpaper",
            subtitle: "Derive a full palette from the current wallpaper and apply it everywhere",
            iconName: "wand.and.stars",
            relevanceScore: 0.75,
            keywords: ["theme", "wallpaper", "generate", "palette", "extract", "aether"]
        ) { _ in
            await self.generateFromWallpaper()
        }
    }
}
