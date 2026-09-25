import Foundation
import OSLog

private let log = Log.module("theme")

/// Renders the `templates:` from config (Omarchy placeholder syntax) and runs each one's
/// `reload` command — the escape hatch for every app without a built-in target (Ghostty,
/// kitty, Alacritty, WezTerm, btop, tmux, Neovim, …). Always also exports the palette to
/// `~/Library/Application Support/Vibeshed/Theme/current/` (`colors.toml`, `colors.json`,
/// `theme.name`) for scripts that want to read it directly.
struct TemplatesTarget: ThemeTarget {
    let id = ThemeTargetID.templates
    let displayName = "Templates"
    var supportsPreview: Bool { true }

    static var exportDirectory: String {
        ThemeFiles.home.appendingPathComponent("Library/Application Support/Vibeshed/Theme/current").path
    }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let templates = request.config.templates.filter { !request.isPreview || $0.preview }
        if !request.isPreview {
            do {
                try Self.export(request.theme)
            } catch {
                return .failed("export: \(error.localizedDescription)")
            }
        }
        guard !templates.isEmpty else { return request.isPreview ? .skipped("none previewable") : .applied() }

        var failures: [String] = []
        for template in templates {
            if let failure = await Self.render(template, theme: request.theme) {
                failures.append(failure)
            }
        }
        return failures.isEmpty ? .applied() : .failed(failures.joined(separator: "; "))
    }

    func snapshot(config: ThemeConfig) async -> ThemeRestore? {
        let previewed = config.templates.filter(\.preview)
        guard !previewed.isEmpty else { return nil }
        let files = ThemeFiles.snapshot(previewed.map { ThemeFiles.expand($0.target) })
        return {
            await files()
            for template in previewed {
                if let reload = template.reload { _ = await ShellCommand.run(reload) }
            }
        }
    }

    /// Returns a failure description, or nil on success.
    private static func render(_ template: ThemeTemplateConfig, theme: ResolvedTheme) async -> String? {
        let source = ThemeFiles.expand(template.source)
        guard let text = ThemeFiles.read(source) else {
            return "\((source as NSString).lastPathComponent): template not found"
        }
        let output = ThemeTemplateRenderer.render(text, palette: theme.palette, themeName: theme.name)
        if !output.unresolved.isEmpty {
            let message = "\(source): unresolved \(output.unresolved.joined(separator: ", "))"
            log.warning("\(message, privacy: .public)")
        }
        do {
            try ThemeFiles.write(output.text, to: ThemeFiles.expand(template.target))
        } catch {
            return "\((template.target as NSString).lastPathComponent): \(error.localizedDescription)"
        }
        if let reload = template.reload {
            let result = await ShellCommand.run(reload, environment: ThemeEnvironment.variables(for: theme))
            if result.status != 0 {
                return "reload '\(reload)' exited \(result.status)"
            }
        }
        return nil
    }

    private static func export(_ theme: ResolvedTheme) throws {
        let variables = theme.palette.templateVariables.sorted { $0.key < $1.key }
        let toml = variables.map { "\($0.key) = \"\($0.value)\"" }.joined(separator: "\n")
        try ThemeFiles.write("# \(theme.name)\n" + toml + "\n", to: "\(exportDirectory)/colors.toml")
        try ThemeFiles.writeJSON(
            ["name": theme.name, "slug": theme.slug, "colors": Dictionary(uniqueKeysWithValues: variables)],
            to: "\(exportDirectory)/colors.json"
        )
        try ThemeFiles.write(theme.name + "\n", to: "\(exportDirectory)/theme.name")
    }
}

/// Runs the `hooks:` shell commands after a (non-preview) apply.
struct HooksTarget: ThemeTarget {
    let id = ThemeTargetID.hooks
    let displayName = "Hooks"

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        guard !request.config.hooks.isEmpty else { return .skipped("none configured") }
        let environment = ThemeEnvironment.variables(for: request.theme)
        var failures: [String] = []
        for hook in request.config.hooks {
            let result = await ShellCommand.run(hook, environment: environment, timeout: 60)
            if result.status != 0 {
                failures.append("'\(hook)' exited \(result.status)")
                log.warning("Theme hook failed: \(result.output, privacy: .public)")
            }
        }
        return failures.isEmpty ? .applied() : .failed(failures.joined(separator: "; "))
    }
}

/// Environment for hooks and template reload commands:
/// `VIBESHED_THEME`, `VIBESHED_THEME_SLUG`, `VIBESHED_THEME_MODE`, `VIBESHED_THEME_DIR`,
/// and `VIBESHED_COLOR_<KEY>` (`#rrggbb`) for every palette key.
enum ThemeEnvironment {
    static func variables(for theme: ResolvedTheme) -> [String: String] {
        var environment = [
            "VIBESHED_THEME": theme.name,
            "VIBESHED_THEME_SLUG": theme.slug,
            "VIBESHED_THEME_MODE": theme.palette.mode.rawValue,
            "VIBESHED_THEME_DIR": TemplatesTarget.exportDirectory,
        ]
        for (key, color) in theme.palette.colors {
            environment["VIBESHED_COLOR_\(key.uppercased())"] = color.hex
        }
        return environment
    }
}
