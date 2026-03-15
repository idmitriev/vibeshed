import Foundation
import OSLog

actor ThemeModule: ModuleConfigurable {
    let id = "theme"
    let displayName = "Theme"
    let iconName = "paintpalette"
    var isEnabled = true

    typealias Config = ThemeConfig
    static var defaultConfig: Config? { .init() }

    private var config: ThemeConfig = .init()
    private var context: ModuleContext?
    private let log = Log.module("theme")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        log.info("Theme module initialized")
    }

    func configDidUpdate(_ config: ThemeConfig) async {
        self.config = config
        log.debug("Config updated")
    }

    static func validate(_ config: ThemeConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if let presets = config.presets {
            let names = presets.map(\.name)
            if Set(names).count != names.count {
                errors.append("Preset names must be unique")
            }
            for preset in presets {
                if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errors.append("Preset name cannot be empty")
                }
                if let appearance = preset.appearance,
                   appearance != "dark" && appearance != "light" {
                    errors.append("Preset '\(preset.name)' appearance must be 'dark' or 'light'")
                }
            }
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        buildActions(config: config)
    }

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        switch parameterID {
        case "color":
            return ThemeManager.accentColors.map { entry in
                ParameterOption(id: entry.name, label: entry.name, iconName: "circle.fill")
            }
        case "theme" where actionID.rawValue == "theme.vscodeTheme":
            return vscodeThemeOptions()
        case "theme" where actionID.rawValue == "theme.jetbrainsTheme":
            return ThemeManager.jetbrainsThemes.map { entry in
                ParameterOption(id: entry.name, label: entry.name, iconName: "paintbrush")
            }
        case "preset":
            return itermPresetOptions()
        case "mode":
            return githubThemeOptions()
        default:
            return []
        }
    }

    // MARK: - Build Actions

    private func buildActions(config: ThemeConfig) -> [ThemeAction] {
        let enabled = config.enabledActions
        var actions: [ThemeAction] = []

        actions.append(contentsOf: buildAppearanceActions())
        actions.append(contentsOf: buildAccentColorAction())
        actions.append(contentsOf: buildWallpaperAction())
        actions.append(contentsOf: buildVSCodeActions())
        actions.append(contentsOf: buildJetBrainsActions())
        actions.append(contentsOf: buildITermActions())
        actions.append(contentsOf: buildGitHubActions())
        actions.append(contentsOf: buildPresetActions(config: config))

        if let enabled {
            return actions.filter { enabled.contains(actionName($0.id)) }
        }
        return actions
    }

    private func actionName(_ id: ActionID) -> String {
        id.actionName
    }

    // MARK: - Appearance

    private func buildAppearanceActions() -> [ThemeAction] {
        [
            ThemeAction(
                id: ActionID(module: "theme", name: "setDark"),
                title: "Set Dark Mode",
                subtitle: "Switch system to dark appearance",
                iconName: "moon.fill",
                relevanceScore: 0.85,
                keywords: ["dark", "mode", "appearance", "theme", "night"],
                category: .system
            ) { _ in
                try ThemeManager.setDarkMode(true)
                return .showResult(title: "Dark Mode", body: "System appearance set to dark")
            },
            ThemeAction(
                id: ActionID(module: "theme", name: "setLight"),
                title: "Set Light Mode",
                subtitle: "Switch system to light appearance",
                iconName: "sun.max.fill",
                relevanceScore: 0.85,
                keywords: ["light", "mode", "appearance", "theme", "day"],
                category: .system
            ) { _ in
                try ThemeManager.setDarkMode(false)
                return .showResult(title: "Light Mode", body: "System appearance set to light")
            },
        ]
    }

    // MARK: - Accent Color

    private func buildAccentColorAction() -> [ThemeAction] {
        [
            ThemeAction(
                id: ActionID(module: "theme", name: "setAccentColor"),
                title: "Set Accent Color",
                subtitle: "Change the system accent color",
                iconName: "paintpalette.fill",
                relevanceScore: 0.8,
                keywords: ["accent", "color", "tint", "highlight", "theme"],
                parameters: [
                    ActionParameter(
                        id: "color",
                        label: "Color",
                        type: .dynamicSelection(hint: "color"),
                        isRequired: true
                    ),
                ],
                category: .system
            ) { values in
                guard let color = values["color"] as? String else {
                    return .keepOpen
                }
                try ThemeManager.setAccentColor(color)
                return .showResult(title: "Accent Color", body: "Set to \(color)")
            },
        ]
    }

    // MARK: - Wallpaper

    private func buildWallpaperAction() -> [ThemeAction] {
        [
            ThemeAction(
                id: ActionID(module: "theme", name: "setWallpaper"),
                title: "Set Wallpaper",
                subtitle: "Change the desktop wallpaper",
                iconName: "photo.fill",
                relevanceScore: 0.75,
                keywords: ["wallpaper", "desktop", "background", "image", "theme"],
                parameters: [
                    ActionParameter(
                        id: "path",
                        label: "Image Path",
                        type: .path(allowsDirectories: false),
                        isRequired: true
                    ),
                ],
                category: .system
            ) { values in
                guard let path = values["path"] as? String else {
                    return .keepOpen
                }
                try ThemeManager.setWallpaper(path: path)
                return .showResult(title: "Wallpaper", body: "Desktop wallpaper updated")
            },
        ]
    }

    // MARK: - VSCode

    private func buildVSCodeActions() -> [ThemeAction] {
        [
            ThemeAction(
                id: ActionID(module: "theme", name: "vscodeTheme"),
                title: "Set VS Code Theme",
                subtitle: "Change the color theme in VS Code",
                iconName: "chevron.left.forwardslash.chevron.right",
                relevanceScore: 0.8,
                keywords: ["vscode", "code", "editor", "color", "theme", "cursor", "windsurf"],
                parameters: [
                    ActionParameter(
                        id: "theme",
                        label: "Theme",
                        type: .dynamicSelection(hint: "theme"),
                        isRequired: true
                    ),
                ],
                category: .vscode
            ) { [config] values in
                guard let themeName = values["theme"] as? String else {
                    return .keepOpen
                }
                let variants = resolveVSCodeVariants(config.vscodeVariants)
                try ThemeManager.setVSCodeTheme(themeName, variants: variants)
                return .showResult(title: "VS Code Theme", body: "Set to \(themeName)")
            },
        ]
    }

    // MARK: - JetBrains

    private func buildJetBrainsActions() -> [ThemeAction] {
        [
            ThemeAction(
                id: ActionID(module: "theme", name: "jetbrainsTheme"),
                title: "Set JetBrains Theme",
                subtitle: "Change the theme in JetBrains IDEs (restart required)",
                iconName: "hammer.fill",
                relevanceScore: 0.75,
                keywords: ["jetbrains", "intellij", "idea", "pycharm", "webstorm", "theme", "darcula"],
                parameters: [
                    ActionParameter(
                        id: "theme",
                        label: "Theme",
                        type: .dynamicSelection(hint: "theme"),
                        isRequired: true
                    ),
                ],
                category: .jetbrains
            ) { [config] values in
                guard let themeName = values["theme"] as? String else {
                    return .keepOpen
                }
                try ThemeManager.setJetBrainsTheme(themeName, enabledIDEs: config.jetbrainsIDEs)
                return .showResult(title: "JetBrains Theme", body: "Set to \(themeName). Restart IDE to apply.")
            },
        ]
    }

    // MARK: - iTerm

    private func buildITermActions() -> [ThemeAction] {
        [
            ThemeAction(
                id: ActionID(module: "theme", name: "itermPreset"),
                title: "Set iTerm Color Preset",
                subtitle: "Change the color preset in iTerm",
                iconName: "terminal.fill",
                relevanceScore: 0.75,
                keywords: ["iterm", "terminal", "color", "preset", "theme"],
                parameters: [
                    ActionParameter(
                        id: "preset",
                        label: "Preset",
                        type: .dynamicSelection(hint: "preset"),
                        isRequired: true
                    ),
                ],
                category: .iterm
            ) { values in
                guard let presetName = values["preset"] as? String else {
                    return .keepOpen
                }
                try ThemeManager.setITermColorPreset(presetName)
                return .showResult(title: "iTerm Preset", body: "Set to \(presetName)")
            },
        ]
    }

    // MARK: - GitHub

    private func buildGitHubActions() -> [ThemeAction] {
        [
            ThemeAction(
                id: ActionID(module: "theme", name: "githubTheme"),
                title: "Set GitHub Theme",
                subtitle: "Change appearance on github.com (requires open tab)",
                iconName: "globe",
                relevanceScore: 0.8,
                keywords: ["github", "theme", "dark", "light", "auto", "appearance"],
                parameters: [
                    ActionParameter(
                        id: "mode",
                        label: "Theme",
                        type: .dynamicSelection(hint: "mode"),
                        isRequired: true
                    ),
                ],
                category: .github
            ) { values in
                guard let mode = values["mode"] as? String else {
                    return .keepOpen
                }
                let result = try ThemeManager.setGitHubTheme(mode)
                switch result {
                case "ok":
                    return .showResult(title: "GitHub Theme", body: "Set to \(mode)")
                case "no_tab":
                    return .showResult(title: "GitHub Theme", body: "Open github.com in a browser first")
                case "no_token":
                    return .showResult(title: "GitHub Theme", body: "Not logged in to GitHub in this tab")
                default:
                    return .showResult(title: "GitHub Theme", body: "Failed: \(result)")
                }
            },
        ]
    }

    // MARK: - Presets

    private func buildPresetActions(config: ThemeConfig) -> [ThemeAction] {
        let presets = config.presets ?? ThemeConfig.defaultPresets
        let vscodeVariants = config.vscodeVariants
        let jetbrainsIDEs = config.jetbrainsIDEs

        return presets.map { preset in
            let stableID = preset.name.lowercased()
                .replacingOccurrences(of: " ", with: "")
            return ThemeAction(
                id: ActionID(module: "theme", name: "preset.\(stableID)"),
                title: preset.name,
                subtitle: preset.subtitle ?? "Apply theme preset",
                iconName: preset.icon ?? "paintpalette",
                relevanceScore: 0.9,
                keywords: ["preset", "theme"] + (preset.keywords ?? []),
                category: .preset(preset)
            ) { _ in
                let variants = resolveVSCodeVariants(vscodeVariants)
                let applied = try await ThemeManager.applyPreset(
                    preset,
                    vscodeVariants: variants,
                    jetbrainsIDEs: jetbrainsIDEs
                )
                let summary = applied.joined(separator: ", ")
                return .showResult(title: preset.name, body: summary)
            }
        }
    }

    // MARK: - Parameter Options

    private func vscodeThemeOptions() -> [ParameterOption] {
        let themes = config.vscodeThemes ?? ThemeConfig.defaultVSCodeThemes
        return themes.map { name in
            ParameterOption(
                id: name,
                label: name,
                iconName: "chevron.left.forwardslash.chevron.right"
            )
        }
    }

    private func itermPresetOptions() -> [ParameterOption] {
        let presets = config.itermPresets ?? ThemeConfig.defaultITermPresets
        return presets.map { name in
            ParameterOption(id: name, label: name, iconName: "terminal")
        }
    }

    private func githubThemeOptions() -> [ParameterOption] {
        ThemeConfig.defaultGitHubThemes.map { name in
            let icon: String
            switch name.lowercased() {
            case "auto": icon = "circle.lefthalf.filled"
            case "light": icon = "sun.max"
            case "dark": icon = "moon.fill"
            case "dark dimmed": icon = "moon"
            default: icon = "globe"
            }
            return ParameterOption(id: name.lowercased(), label: name, iconName: icon)
        }
    }
}

// MARK: - VSCode Variant Resolution

private func resolveVSCodeVariants(
    _ configured: [String: String]?
) -> [(name: String, dir: String)] {
    if let configured {
        return configured.map { (name: $0.key, dir: $0.value) }
    }
    return [
        (name: "VS Code", dir: "Code"),
        (name: "VS Code Insiders", dir: "Code - Insiders"),
        (name: "Cursor", dir: "Cursor"),
        (name: "Windsurf", dir: "Windsurf"),
    ]
}
