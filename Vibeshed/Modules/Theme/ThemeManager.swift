import AppKit
import Foundation
import OSLog

private let log = Log.module("theme")

enum ThemeManager {

    // MARK: - Accent Colors

    struct AccentColor: Sendable {
        let name: String
        let value: Int
        let sfColor: String
    }

    static let accentColors: [AccentColor] = [
        .init(name: "Blue", value: 4, sfColor: "circle.fill"),
        .init(name: "Purple", value: 5, sfColor: "circle.fill"),
        .init(name: "Pink", value: 6, sfColor: "circle.fill"),
        .init(name: "Red", value: 0, sfColor: "circle.fill"),
        .init(name: "Orange", value: 1, sfColor: "circle.fill"),
        .init(name: "Yellow", value: 2, sfColor: "circle.fill"),
        .init(name: "Green", value: 3, sfColor: "circle.fill"),
        .init(name: "Graphite", value: -1, sfColor: "circle.fill"),
    ]

    // MARK: - JetBrains Themes

    struct JBTheme: Sendable {
        let name: String
        let className: String
    }

    static let jetbrainsThemes: [JBTheme] = [
        .init(name: "Darcula", className: "com.intellij.ide.ui.laf.darcula.DarculaLaf"),
        .init(name: "IntelliJ Light", className: "com.intellij.ide.ui.laf.IntelliJLaf"),
        .init(name: "High Contrast", className: "com.intellij.ide.ui.laf.intellij.HighContrastLaf"),
    ]

    // MARK: - System Appearance

    static func setDarkMode(_ enabled: Bool) throws {
        let flag = enabled ? "true" : "false"
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to \(flag)
            end tell
        end tell
        """
        try runAppleScript(script)
    }

    // MARK: - Accent Color

    static func setAccentColor(_ name: String) throws {
        guard let color = accentColors.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            log.warning("Unknown accent color: \(name, privacy: .public)")
            return
        }

        try runDefaults(["write", "NSGlobalDomain", "AppleAccentColor", "-int", String(color.value)])
        try runDefaults(["delete", "NSGlobalDomain", "AppleHighlightColor"])

        // Nudge the system to pick up the change
        let script = """
        tell application "System Events"
            tell appearance preferences
                set dark mode to dark mode
            end tell
        end tell
        """
        try? runAppleScript(script)
    }

    // MARK: - Wallpaper

    static func setWallpaper(path: String) throws {
        let expanded = NSString(string: path).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            log.warning("Wallpaper file not found: \(expanded, privacy: .public)")
            throw ThemeError.fileNotFound(expanded)
        }

        let script = """
        tell application "System Events"
            tell every desktop
                set picture to "\(expanded)"
            end tell
        end tell
        """
        try runAppleScript(script)
    }

    // MARK: - VSCode Theme

    static func setVSCodeTheme(
        _ themeName: String,
        variants: [(name: String, dir: String)]
    ) throws {
        let fm = FileManager.default
        let appSupport = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        var applied = 0

        for variant in variants {
            let settingsPath = appSupport
                .appendingPathComponent(variant.dir)
                .appendingPathComponent("User/settings.json")
                .path

            guard fm.fileExists(atPath: settingsPath) else { continue }
            guard let data = fm.contents(atPath: settingsPath) else { continue }

            do {
                guard var json = try JSONSerialization.jsonObject(
                    with: data, options: .mutableContainers
                ) as? [String: Any] else {
                    continue
                }
                json["workbench.colorTheme"] = themeName
                let output = try JSONSerialization.data(
                    withJSONObject: json,
                    options: [.prettyPrinted, .sortedKeys]
                )
                try output.write(to: URL(fileURLWithPath: settingsPath))
                applied += 1
                log.info("Set \(variant.name, privacy: .public) theme to \(themeName, privacy: .public)")
            } catch {
                log.warning("Failed to update \(variant.name, privacy: .public) settings: \(error.localizedDescription, privacy: .public)")
            }
        }

        if applied == 0 {
            log.info("No VSCode variants found to update")
        }
    }

    // MARK: - JetBrains Theme

    static func setJetBrainsTheme(
        _ themeName: String,
        enabledIDEs: Set<String>?
    ) throws {
        let theme = jetbrainsThemes.first { $0.name == themeName }
        let className = theme?.className ?? themeName

        let fm = FileManager.default
        let jbBase = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/JetBrains")

        guard let contents = try? fm.contentsOfDirectory(atPath: jbBase.path) else {
            log.debug("No JetBrains Application Support directory found")
            return
        }

        var applied = 0

        for dir in contents {
            guard let ideInfo = matchJetBrainsIDE(dir) else { continue }
            if let enabled = enabledIDEs, !enabled.contains(ideInfo.tag) {
                continue
            }

            let lafPath = jbBase
                .appendingPathComponent(dir)
                .appendingPathComponent("options/laf.xml")
                .path

            do {
                try writeLafXML(at: lafPath, className: className)
                applied += 1
                log.info("Set \(ideInfo.displayName, privacy: .public) theme to \(themeName, privacy: .public)")
            } catch {
                log.warning("Failed to update \(ideInfo.displayName, privacy: .public) laf.xml: \(error.localizedDescription, privacy: .public)")
            }
        }

        if applied == 0 {
            log.info("No JetBrains IDEs found to update")
        }
    }

    // MARK: - iTerm Color Preset

    static func setITermColorPreset(_ presetName: String) throws {
        let escaped = presetName.escapedForAppleScript
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        tell s
                            set color preset to "\(escaped)"
                        end tell
                    end repeat
                end repeat
            end repeat
        end tell
        """
        try runAppleScript(script)
    }

    // MARK: - GitHub Theme

    /// Set GitHub's appearance theme by injecting JavaScript into an open github.com tab.
    /// Returns a human-readable result: "ok", "no_tab", or error detail.
    static func setGitHubTheme(_ theme: String) throws -> String {
        let body = buildGitHubBody(theme)
        let js = buildGitHubJS(body: body)
        let escapedJS = js.escapedForAppleScript

        // Try running browsers with AppleScript tab support
        let browsers = BrowserRegistry.appleScriptCapable.filter {
            BrowserRegistry.isRunning($0.bundleID)
        }

        for browser in browsers {
            let script = browser.bundleID == "com.apple.Safari"
                ? safariGitHubScript(js: escapedJS)
                : chromiumGitHubScript(bundleID: browser.bundleID, js: escapedJS)
            let result = AppleScriptRunner.runSyncWithOutput(script)
            if let result, !result.isEmpty, result != "missing value" {
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == "ok" || trimmed.hasPrefix("err:") || trimmed == "no_token" {
                    return trimmed
                }
            }
        }

        return "no_tab"
    }

    private static func buildGitHubBody(_ theme: String) -> String {
        let lower = theme.lowercased()
        switch lower {
        case "auto":
            return "color_mode=auto"
        case "light", "dark", "dark_dimmed", "dark dimmed":
            let name = lower.replacingOccurrences(of: " ", with: "_")
            return "color_mode=single&single_theme_name=\(name)"
        default:
            return "color_mode=single&single_theme_name=\(lower)"
        }
    }

    private static func buildGitHubJS(body: String) -> String {
        // Minified async IIFE that fetches CSRF token and PUTs to /settings/appearance
        """
        (async()=>{var t=document.querySelector('meta[name=csrf-token]');\
        if(!t)return 'no_token';\
        var r=await fetch('/settings/appearance',{\
        method:'PUT',\
        headers:{'Content-Type':'application/x-www-form-urlencoded',\
        'X-CSRF-Token':t.content,'Accept':'application/json'},\
        body:'\(body)'});\
        return r.ok?'ok':'err:'+r.status})()
        """
    }

    private static func chromiumGitHubScript(bundleID: String, js: String) -> String {
        """
        tell application id "\(bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t starts with "https://github.com" then
                        return execute t javascript "\(js)"
                    end if
                end repeat
            end repeat
        end tell
        return "missing value"
        """
    }

    private static func safariGitHubScript(js: String) -> String {
        """
        tell application "Safari"
            repeat with w in windows
                repeat with t in tabs of w
                    if URL of t starts with "https://github.com" then
                        return do JavaScript "\(js)" in t
                    end if
                end repeat
            end repeat
        end tell
        return "missing value"
        """
    }

    // MARK: - Apply Preset

    static func applyPreset(
        _ preset: ThemePreset,
        vscodeVariants: [(name: String, dir: String)],
        jetbrainsIDEs: Set<String>?
    ) async throws -> [String] {
        var applied: [String] = []

        if let appearance = preset.appearance {
            let isDark = appearance.lowercased() == "dark"
            try setDarkMode(isDark)
            applied.append(isDark ? "Dark mode" : "Light mode")
        }

        if let accent = preset.accentColor {
            try setAccentColor(accent)
            applied.append("Accent: \(accent)")
        }

        if let wallpaper = preset.wallpaper {
            try setWallpaper(path: wallpaper)
            applied.append("Wallpaper set")
        }

        if let vscode = preset.vscodeTheme {
            try setVSCodeTheme(vscode, variants: vscodeVariants)
            applied.append("VS Code: \(vscode)")
        }

        if let jb = preset.jetbrainsTheme {
            try setJetBrainsTheme(jb, enabledIDEs: jetbrainsIDEs)
            applied.append("JetBrains: \(jb)")
        }

        if let iterm = preset.itermPreset {
            try setITermColorPreset(iterm)
            applied.append("iTerm: \(iterm)")
        }

        if let github = preset.githubTheme {
            let result = try setGitHubTheme(github)
            switch result {
            case "ok":
                applied.append("GitHub: \(github)")
            case "no_tab":
                applied.append("GitHub: skipped (no tab open)")
            case "no_token":
                applied.append("GitHub: skipped (not logged in)")
            default:
                applied.append("GitHub: \(result)")
            }
        }

        return applied
    }

    // MARK: - Private Helpers

    private static func runAppleScript(_ source: String) throws {
        try AppleScriptRunner.runSync(source)
    }

    private static func runDefaults(_ args: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = args
        try task.run()
        task.waitUntilExit()
    }

    private static func matchJetBrainsIDE(_ dirName: String) -> JetBrainsIDEInfo? {
        for info in JetBrainsIDEInfo.known {
            if dirName.hasPrefix(info.dirPrefix) {
                let suffix = String(dirName.dropFirst(info.dirPrefix.count))
                if suffix.isEmpty || suffix.first?.isNumber == true {
                    return info
                }
            }
        }
        return nil
    }

    private static func writeLafXML(at path: String, className: String) throws {
        let xml = """
        <application>
          <component name="LafManager">
            <laf class-name="\(className)" />
          </component>
        </application>
        """

        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        try xml.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Errors

enum ThemeError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): "File not found: \(path)"
        }
    }
}
