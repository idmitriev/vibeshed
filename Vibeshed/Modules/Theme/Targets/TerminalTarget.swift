import AppKit
import Foundation

/// Terminal.app: keeps a "Vibeshed" profile in Terminal's preferences — a copy of the
/// user's own default profile (font, size, behaviour) with the theme's colors — and,
/// unless `terminalDefaultProfile: false`, makes it the default and startup profile
/// (see `TerminalProfiles`). `apps: { terminal: "<profile>" }` uses one of Terminal's
/// own profiles instead.
///
/// Terminal reads profiles only at launch, and its AppleScript can neither create a
/// profile nor set ANSI or selection colors. (Opening a `.terminal` file would import it,
/// but adds a numbered copy on every import.) So a running Terminal gets background, text,
/// bold and cursor colors on every tab over AppleScript, and the full palette the next
/// time it launches: `ThemeModule` rewrites the profile whenever Terminal quits (it may
/// write back its in-memory copy) and moves every tab onto it once Terminal has launched.
struct TerminalTarget: ThemeTarget {
    let id = ThemeTargetID.terminal
    let displayName = "Terminal"
    var supportsPreview: Bool {
        true
    }

    static let bundleID = "com.apple.Terminal"
    static let profileName = "Vibeshed"

    /// Profile key → palette color, for everything a Terminal profile colors.
    static func profileColors(_ palette: ThemePalette) -> [(key: String, color: ThemeColor)] {
        let names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        var list: [(String, ThemeColor)] = [
            ("BackgroundColor", palette.background),
            ("TextColor", palette.foreground),
            ("TextBoldColor", palette.brightForeground),
            ("CursorColor", palette.cursor),
            ("SelectionColor", palette.selectionBackground),
        ]
        for (index, color) in palette.ansi.enumerated() {
            list.append(("ANSI\(index >= 8 ? "Bright" : "")\(names[index % 8])Color", color))
        }
        return list
    }

    /// The colors AppleScript can set, on tabs and on settings sets alike.
    private static let scriptProperties = ["background color", "normal text color", "bold text color", "cursor color"]

    private static func scriptColors(_ palette: ThemePalette) -> [(property: String, color: ThemeColor)] {
        Array(zip(scriptProperties, [palette.background, palette.foreground, palette.brightForeground, palette.cursor]))
    }

    func apply(_ request: ThemeApplyRequest) async -> ThemeTargetOutcome {
        let isRunning = ThemeApps.isRunning(Self.bundleID)
        if request.isPreview {
            guard isRunning else { return .skipped("not running") }
            return await Self.run(Self.forEachTab(Self.assignments(request.palette)))
        }

        if let profile = request.override(.terminal) {
            if request.config.terminalDefaultProfile {
                TerminalProfiles.setDefault(profile)
            } else {
                TerminalProfiles.restoreDefault()
            }
            guard isRunning else { return .applied() }
            return await Self.run(Self.useProfileScript(profile, makeDefault: request.config.terminalDefaultProfile))
        }

        // Retint the running Terminal first: changing its copy of the profile makes it
        // write its own (stale-ANSI) version back to the preferences.
        if isRunning {
            let script = Self.liveScript(request.palette, makeDefault: request.config.terminalDefaultProfile)
            if case let .failed(message) = await Self.run(script) { return .failed(message) }
        }
        do {
            let parent = TerminalProfiles.parentProfile()
            let font = CommittedFont.current.flatMap { font in
                TerminalFontTarget.font(font.terminalFamily, like: TerminalProfiles.parentFont())
            }
            try TerminalProfiles.write(Self.profile(request.palette, parent: parent, font: font))
        } catch {
            return .failed("profile: \(error.localizedDescription)")
        }
        if request.config.terminalDefaultProfile {
            TerminalProfiles.setDefault(Self.profileName)
        } else {
            TerminalProfiles.restoreDefault()
        }
        return .applied(note: isRunning ? "ANSI and selection colors follow when Terminal next launches" : nil)
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        guard ThemeApps.isRunning(Self.bundleID) else { return nil }
        let reads = Self.scriptProperties.map { "set out to out & \"|\" & (\($0) of t as string)" }
        let script = """
        set out to ""
        set AppleScript's text item delimiters to ", "
        tell application id "\(Self.bundleID)"
            repeat with w in windows
                try
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        set out to out & (id of w as string) & "|" & i
                        \(reads.joined(separator: "\n"))
                        set out to out & linefeed
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
        guard let output = try? await AppleScriptRunner.run(script) else { return nil }

        // One line per tab: windowID|tabIndex|r, g, b|r, g, b|…
        var blocks: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == Self.scriptProperties.count + 2 else { continue }
            let sets = zip(Self.scriptProperties, fields.dropFirst(2)).map { "set \($0) of t to {\($1)}" }
            blocks.append("""
            try
                set t to tab \(fields[1]) of window id \(fields[0])
                \(sets.joined(separator: "\n"))
            end try
            """)
        }
        guard !blocks.isEmpty else { return nil }
        let restore = "tell application id \"\(Self.bundleID)\"\n\(blocks.joined(separator: "\n"))\nend tell"
        return { _ = try? await AppleScriptRunner.run(restore) }
    }

    // MARK: - Profile

    /// The Vibeshed profile: `parent`'s settings with the palette's colors (and the font
    /// `theme/switchFont` applied). Terminal's dynamic ANSI foreground adjustment is
    /// switched off so the palette shows as is.
    static func profile(_ palette: ThemePalette, parent: [String: Any]?, font: NSFont? = nil) -> [String: Any] {
        var profile = baseProfile(parent: parent)
        profile["DynamicANSIForegroundColors"] = false
        for entry in profileColors(palette) {
            profile[entry.key] = try? NSKeyedArchiver.archivedData(
                withRootObject: entry.color.nsColor, requiringSecureCoding: true
            )
        }
        if let font {
            profile["Font"] = try? NSKeyedArchiver.archivedData(withRootObject: font, requiringSecureCoding: true)
        }
        return profile
    }

    /// The Vibeshed profile with nothing of its own: a copy of `parent`.
    static func baseProfile(parent: [String: Any]?) -> [String: Any] {
        var profile = parent ?? [:]
        profile["name"] = profileName
        profile["type"] = "Window Settings"
        if profile["ProfileCurrentVersion"] == nil { profile["ProfileCurrentVersion"] = 2.09 }
        return profile
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

    private static func assignments(_ palette: ThemePalette, of object: String = "t") -> String {
        scriptColors(palette).map { "set \($0.property) of \(object) to \($0.color.appleScriptList)" }
            .joined(separator: "\n")
    }

    /// Runs `body` with `t` bound to every tab. Windows without tabs (Settings) are skipped.
    private static func forEachTab(_ body: String, prelude: String = "") -> String {
        """
        tell application id "\(bundleID)"
            \(prelude)
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        \(body)
                    end repeat
                end try
            end repeat
        end tell
        """
    }

    /// When the running Terminal already knows the Vibeshed profile (it existed when
    /// Terminal launched), recolors it and moves every tab onto it — tabs then keep its
    /// ANSI colors too. Otherwise recolors the tabs themselves.
    private static func liveScript(_ palette: ThemePalette, makeDefault: Bool) -> String {
        let defaults = makeDefault ? "set default settings to p\nset startup settings to p" : ""
        return forEachTab("""
        if p is missing value then
            \(assignments(palette))
        else
            set current settings of t to p
        end if
        """, prelude: """
        set p to missing value
        if exists settings set "\(profileName)" then
            set p to settings set "\(profileName)"
            \(assignments(palette, of: "p"))
            \(defaults)
        end if
        """)
    }

    private static func useProfileScript(_ name: String, makeDefault: Bool) -> String {
        let defaults = makeDefault ? "set default settings to p\nset startup settings to p" : ""
        return forEachTab("set current settings of t to p", prelude: """
        set p to settings set "\(name.escapedForAppleScript)"
        \(defaults)
        """)
    }
}

/// Terminal's profile preferences (`com.apple.Terminal`), as far as the theme needs them:
/// the Vibeshed profile itself, and which profiles new and startup windows use.
enum TerminalProfiles {
    static let domain = TerminalTarget.bundleID
    private static let profilesKey = "Window Settings"
    private static let defaultKeys = ["Default Window Settings", "Startup Window Settings"]
    /// Vibeshed's own defaults: the user's default/startup profiles before Vibeshed took
    /// over, and the profile Vibeshed last made the default.
    private static let previousDefaultKey = "theme.terminal.previousDefaultProfiles"
    private static let appliedDefaultKey = "theme.terminal.appliedDefaultProfile"

    static func write(_ profile: [String: Any]) throws {
        var profiles = SystemPreferences.value(profilesKey, domain: domain) as? [String: Any] ?? [:]
        profiles[TerminalTarget.profileName] = profile
        guard SystemPreferences.set(profiles, forKey: profilesKey, domain: domain) else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    /// The settings the Vibeshed profile copies: the user's own default profile.
    static func parentProfile() -> [String: Any]? {
        guard let name = userDefaults()?[defaultKeys[0]] else { return nil }
        let profiles = SystemPreferences.value(profilesKey, domain: domain) as? [String: Any]
        return profiles?[name] as? [String: Any]
    }

    /// The font of the user's own default profile.
    static func parentFont() -> NSFont? {
        guard let data = parentProfile()?["Font"] as? Data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: data)
    }

    /// The Vibeshed profile as last written.
    static func vibeshedProfile() -> [String: Any]? {
        let profiles = SystemPreferences.value(profilesKey, domain: domain) as? [String: Any]
        return profiles?[TerminalTarget.profileName] as? [String: Any]
    }

    /// Makes `profile` the default and startup profile, remembering the user's own.
    /// Read by Terminal at launch (a running one is switched over AppleScript).
    static func setDefault(_ profile: String) {
        _ = userDefaults()
        for key in defaultKeys {
            SystemPreferences.set(profile, forKey: key, domain: domain)
        }
        UserDefaults.standard.set(profile, forKey: appliedDefaultKey)
    }

    /// Hands the default and startup roles back to the user's own profiles.
    static func restoreDefault() {
        guard let applied = UserDefaults.standard.string(forKey: appliedDefaultKey) else { return }
        let previous = UserDefaults.standard.dictionary(forKey: previousDefaultKey) as? [String: String] ?? [:]
        for key in defaultKeys where SystemPreferences.value(key, domain: domain) as? String == applied {
            SystemPreferences.set(previous[key], forKey: key, domain: domain)
        }
        UserDefaults.standard.removeObject(forKey: appliedDefaultKey)
        UserDefaults.standard.removeObject(forKey: previousDefaultKey)
    }

    /// The user's own default/startup profile names. While they're still in place they're
    /// (re)captured — the user may have picked others since — otherwise the remembered ones.
    private static func userDefaults() -> [String: String]? {
        let applied = UserDefaults.standard.string(forKey: appliedDefaultKey)
        let current = defaultKeys.reduce(into: [String: String]()) { names, key in
            names[key] = SystemPreferences.value(key, domain: domain) as? String
        }
        let isUsers = current[defaultKeys[0]].map { $0 != applied && $0 != TerminalTarget.profileName } ?? false
        if isUsers {
            UserDefaults.standard.set(current, forKey: previousDefaultKey)
            return current
        }
        return UserDefaults.standard.dictionary(forKey: previousDefaultKey) as? [String: String]
    }
}
