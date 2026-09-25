import Foundation

/// Claude Code: writes `~/.claude/themes/vibeshed.json` — a custom theme Claude Code
/// hot-reloads in running sessions — and selects it with `"theme": "custom:vibeshed"`
/// in `~/.claude/settings.json`. Token mapping follows Omarchy's `claude.json.tpl`.
/// `apps: { claude: "dark" }` (or any built-in theme name) selects that instead.
struct ClaudeCodeTarget: ThemeTarget {
    let id = ThemeTargetID.claude
    let displayName = "Claude Code"
    var supportsPreview: Bool { true }

    private static var configDir: String {
        ThemeFiles.home.appendingPathComponent(".claude").path
    }

    private static var settingsPath: String { "\(configDir)/settings.json" }
    private static var themePath: String { "\(configDir)/themes/vibeshed.json" }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        guard ThemeFiles.exists(Self.configDir) else { return .skipped("not installed") }
        do {
            let selection: String
            if let override = request.override(.claude) {
                selection = override
            } else {
                try ThemeFiles.writeJSON(Self.theme(request.palette), to: Self.themePath)
                selection = "custom:vibeshed"
            }
            var settings = JSONCDocument(text: ThemeFiles.read(Self.settingsPath))
            try settings.setValue(selection, forKey: "theme")
            try ThemeFiles.write(settings.text, to: Self.settingsPath)
            return .applied()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        ThemeFiles.snapshot([Self.settingsPath, Self.themePath])
    }

    static func theme(_ palette: ThemePalette) -> [String: Any] {
        let bg = palette.background
        let fg = palette.foreground
        let mix = { (from: ThemeColor, to: ThemeColor, amount: Double) in from.mix(to, amount).hex }
        let overrides: [String: String] = [
            "claude": palette.accent.hex,
            "claudeShimmer": mix(palette.accent, fg, 0.35),
            "text": fg.hex,
            "inverseText": bg.hex,
            "inactive": mix(fg, bg, 0.4),
            "inactiveShimmer": mix(fg, bg, 0.25),
            "subtle": palette.muted.hex,
            "suggestion": palette.cyan.hex,
            "permission": palette.blue.hex,
            "permissionShimmer": mix(palette.blue, fg, 0.35),
            "remember": palette.yellow.hex,
            "success": palette.green.hex,
            "error": palette.red.hex,
            "warning": palette.yellow.hex,
            "warningShimmer": mix(palette.yellow, fg, 0.35),
            "merged": palette.magenta.hex,
            "promptBorder": palette.accent.hex,
            "promptBorderShimmer": mix(palette.accent, fg, 0.35),
            "planMode": palette.cyan.hex,
            "autoAccept": palette.yellow.hex,
            "bashBorder": (palette["bright_yellow"] ?? palette.yellow).hex,
            "ide": (palette["bright_cyan"] ?? palette.cyan).hex,
            "diffAdded": mix(bg, palette.green, 0.15),
            "diffRemoved": mix(bg, palette.red, 0.15),
            "diffAddedDimmed": mix(bg, palette.green, 0.08),
            "diffRemovedDimmed": mix(bg, palette.red, 0.08),
            "diffAddedWord": mix(bg, palette.green, 0.32),
            "diffRemovedWord": mix(bg, palette.red, 0.32),
            "userMessageBackground": mix(bg, fg, 0.06),
            "userMessageBackgroundHover": mix(bg, fg, 0.1),
            "bashMessageBackgroundColor": mix(bg, fg, 0.06),
            "memoryBackgroundColor": mix(bg, fg, 0.06),
            "selectionBg": palette.selectionBackground.hex,
            "rate_limit_fill": palette.accent.hex,
            "rate_limit_empty": mix(bg, fg, 0.2),
            "briefLabelYou": palette.yellow.hex,
            "briefLabelClaude": palette.accent.hex,
        ]
        return ["name": "Vibeshed", "base": palette.mode.rawValue, "overrides": overrides]
    }
}

/// github.com's appearance setting, changed through a logged-in browser tab (injected
/// fetch against `/settings/appearance`). Off by default — it rewrites an account
/// setting — enable it with `targets:` or a theme's `apps: { github: … }`.
struct GitHubWebTarget: ThemeTarget {
    let id = ThemeTargetID.github
    let displayName = "GitHub"

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let theme = request.override(.github) ?? request.palette.mode.rawValue
        let body = theme.lowercased() == "auto"
            ? "color_mode=auto"
            : "color_mode=single&single_theme_name=\(theme.lowercased().replacingOccurrences(of: " ", with: "_"))"
        let js = """
        (async()=>{var t=document.querySelector('meta[name=csrf-token]');\
        if(!t)return 'no_token';\
        var r=await fetch('/settings/appearance',{method:'PUT',\
        headers:{'Content-Type':'application/x-www-form-urlencoded','X-CSRF-Token':t.content,\
        'Accept':'application/json'},body:'\(body)'});\
        return r.ok?'ok':'err:'+r.status})()
        """.escapedForAppleScript

        for browser in BrowserRegistry.appleScriptCapable where BrowserRegistry.isRunning(browser.bundleID) {
            let script = browser.bundleID == "com.apple.Safari"
                ? tabScript(app: "application \"Safari\"", run: "do JavaScript \"\(js)\" in t")
                : tabScript(app: "application id \"\(browser.bundleID)\"", run: "execute t javascript \"\(js)\"")
            let result = (try? await AppleScriptRunner.run(script))?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch result {
            case "ok": return .applied()
            case "no_token": return .skipped("not signed in to GitHub")
            case let error? where error.hasPrefix("err:"): return .failed("GitHub replied \(error.dropFirst(4))")
            default: continue
            }
        }
        return .skipped("no github.com tab open")
    }

    private func tabScript(app: String, run: String) -> String {
        """
        tell \(app)
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t starts with "https://github.com" then return \(run)
                end repeat
            end repeat
        end tell
        return "missing value"
        """
    }
}
