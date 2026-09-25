import Foundation

/// iTerm2: recolors every open session live over AppleScript, and keeps a "Vibeshed"
/// Dynamic Profile in sync (iTerm reloads those on change). That profile inherits
/// everything but colors from the user's own default profile and — unless
/// `itermDefaultProfile: false` — becomes iTerm's default, so new windows and iTerm
/// restarts keep the theme (see `ITermProfiles`).
/// `apps: { iterm: "<preset>" }` applies a built-in/imported color preset instead.
struct ITermTarget: ThemeTarget {
    let id = ThemeTargetID.iterm
    let displayName = "iTerm"
    var supportsPreview: Bool { true }

    static let bundleID = "com.googlecode.iterm2"
    static let profileGUID = "vibeshed-theme-profile"

    /// AppleScript session property → palette color, and the matching Dynamic Profile key.
    private static func colors(_ palette: ThemePalette) -> [(property: String, profileKey: String, color: ThemeColor)] {
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        var list: [(String, String, ThemeColor)] = [
            ("background color", "Background Color", palette.background),
            ("foreground color", "Foreground Color", palette.foreground),
            ("bold color", "Bold Color", palette.brightForeground),
            ("cursor color", "Cursor Color", palette.cursor),
            ("cursor text color", "Cursor Text Color", palette.background),
            ("selection color", "Selection Color", palette.selectionBackground),
            ("selected text color", "Selected Text Color", palette.selectionForeground),
        ]
        for (index, color) in palette.ansi.enumerated() {
            let name = (index >= 8 ? "bright " : "") + names[index % 8]
            list.append(("ANSI \(name) color", "Ansi \(index) Color", color))
        }
        return list
    }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        guard ThemeApps.isInstalled(Self.bundleID) else { return .skipped("not installed") }

        if let preset = request.override(.iterm) {
            guard ThemeApps.isRunning(Self.bundleID) else { return .skipped("not running") }
            return await Self.run(Self.presetScript(preset))
        }

        if !request.isPreview {
            do {
                // Resolve the parent before the default moves to the Vibeshed profile.
                let parent = ITermProfiles.parentProfileName()
                let profile = Self.profile(request.palette, parent: parent)
                try ThemeFiles.writeJSON(["Profiles": [profile]], to: Self.profilePath)
            } catch {
                return .failed("dynamic profile: \(error.localizedDescription)")
            }
            ITermProfiles.setVibeshedDefault(request.config.itermDefaultProfile)
        }
        guard ThemeApps.isRunning(Self.bundleID) else { return .applied() }
        let assignments = Self.colors(request.palette).map { "set \($0.property) to \($0.color.appleScriptList)" }
        return await Self.run(Self.forEachSession(assignments.joined(separator: "\n")))
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        guard ThemeApps.isRunning(Self.bundleID) else { return nil }
        let properties = Self.colors(ThemePalette.placeholder).map(\.property)
        let reads = properties.map { "set out to out & \"|\" & (\($0) as string)" }.joined(separator: "\n")
        let script = Self.forEachSession("""
        set out to out & (id as string)
        \(reads)
        set out to out & linefeed
        """, prelude: "set out to \"\"\nset AppleScript's text item delimiters to \", \"", result: "return out")
        guard let output = try? await AppleScriptRunner.run(script) else { return nil }

        // One line per session: id|r, g, b|r, g, b|…
        var blocks: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == properties.count + 1 else { continue }
            let sets = zip(properties, fields.dropFirst()).map { "set \($0) to {\($1)}" }.joined(separator: "\n")
            blocks.append("if id of s is \"\(fields[0])\" then\ntell s\n\(sets)\nend tell\nend if")
        }
        guard !blocks.isEmpty else { return nil }
        let restore = Self.forEachSession(blocks.joined(separator: "\n"), tellSession: false)
        return { _ = try? await AppleScriptRunner.run(restore) }
    }

    // MARK: - Scripts

    private static func run(_ script: String) async -> ThemeTargetOutcome {
        do {
            try await AppleScriptRunner.run(script, timeout: 10)
            return .applied()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func forEachSession(
        _ body: String,
        tellSession: Bool = true,
        prelude: String = "",
        result: String = ""
    ) -> String {
        let inner = tellSession ? "tell s\n\(body)\nend tell" : body
        return """
        \(prelude)
        tell application id "\(bundleID)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        \(inner)
                    end repeat
                end repeat
            end repeat
        end tell
        \(result)
        """
    }

    private static func presetScript(_ preset: String) -> String {
        forEachSession("set color preset to \"\(preset.escapedForAppleScript)\"")
    }

    // MARK: - Dynamic Profile

    static var profilePath: String {
        ThemeFiles.home
            .appendingPathComponent("Library/Application Support/iTerm2/DynamicProfiles/vibeshed-theme.json").path
    }

    /// The Dynamic Profile: palette colors on top of the parent profile. Separate
    /// light/dark colors are switched off explicitly — a parent with them on would
    /// otherwise make iTerm read its own "(Dark)"/"(Light)" keys and ignore these.
    static func profile(_ palette: ThemePalette, parent: String?) -> [String: Any] {
        var profile: [String: Any] = [
            "Name": "Vibeshed",
            "Guid": profileGUID,
            "Use Separate Colors for Light and Dark Mode": false,
        ]
        if let parent { profile["Dynamic Profile Parent Name"] = parent }
        for entry in colors(palette) {
            profile[entry.profileKey] = [
                "Red Component": entry.color.red,
                "Green Component": entry.color.green,
                "Blue Component": entry.color.blue,
                "Alpha Component": 1,
                "Color Space": "sRGB",
            ]
        }
        return profile
    }
}

private extension ThemePalette {
    /// Only used for the property list, where the colors are irrelevant.
    static let placeholder: ThemePalette = (try? ThemePalette.resolve(
        ["background": "#000000", "foreground": "#ffffff", "red": "#ff0000", "green": "#00ff00",
         "yellow": "#ffff00", "blue": "#0000ff", "magenta": "#ff00ff", "cyan": "#00ffff"]
    )) ?? ThemePalette(mode: .dark, colors: [:])
}
