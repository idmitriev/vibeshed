import AppKit
import Foundation

// MARK: - iTerm

/// iTerm: sets the font of the "Vibeshed" Dynamic Profile — the one the theme colors and
/// makes the default (see `ITermTarget`; with no theme applied it's your default profile
/// as is). iTerm reloads Dynamic Profiles when the file changes, and the face keeps the
/// weight and size of your own default profile's font.
struct ITermFontTarget: FontTarget {
    let id = ThemeTargetID.iterm
    let displayName = "iTerm"
    var supportsPreview: Bool { true }

    func apply(_ request: FontApplyRequest) async -> ThemeTargetOutcome {
        guard ThemeApps.isInstalled(ITermTarget.bundleID) else { return .skipped("not installed") }
        let family = request.font.terminalFamily
        guard let font = Self.normalFont(family, like: ITermProfiles.parentNormalFont()) else {
            return .failed("\(family) has no upright face")
        }
        do {
            var profile = ITermTarget.storedProfile()
                ?? ITermTarget.baseProfile(parent: ITermProfiles.parentProfileName())
            profile["Normal Font"] = font
            try ThemeFiles.writeJSON(["Profiles": [profile]], to: ITermTarget.profilePath)
        } catch {
            return .failed("dynamic profile: \(error.localizedDescription)")
        }
        if !request.isPreview {
            ITermProfiles.setVibeshedDefault(request.config.itermDefaultProfile)
        }
        return .applied()
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        ThemeFiles.snapshot([ITermTarget.profilePath])
    }

    func currentFamily(config _: ThemeConfig) -> String? {
        guard ThemeApps.isInstalled(ITermTarget.bundleID),
              let face = ITermProfiles.parentNormalFont()?.split(separator: " ").dropLast().joined(separator: " ")
        else { return nil }
        return FontFaces.family(ofFace: face)
    }

    /// iTerm's `"<PostScript name> <size>"` for `family`, in the weight and size of
    /// `reference` (another font in that format; iTerm's default without one).
    static func normalFont(_ family: String, like reference: String?) -> String? {
        var parts = (reference ?? "Monaco 12").split(separator: " ").map(String.init)
        let size = parts.count > 1 ? parts.removeLast() : "12"
        guard let face = FontFaces.face(of: family, like: parts.joined(separator: " ")) else { return nil }
        return "\(face) \(size)"
    }
}

// MARK: - Terminal

/// Terminal.app: sets the font of every open tab over AppleScript, and of the "Vibeshed"
/// profile (see `TerminalTarget`), made the default and startup profile as the theme
/// does. The face keeps the weight and size of your default profile's font.
struct TerminalFontTarget: FontTarget {
    let id = ThemeTargetID.terminal
    let displayName = "Terminal"
    var supportsPreview: Bool { true }

    private static var bundleID: String { TerminalTarget.bundleID }

    func apply(_ request: FontApplyRequest) async -> ThemeTargetOutcome {
        let isRunning = ThemeApps.isRunning(Self.bundleID)
        if request.isPreview, !isRunning { return .skipped("not running") }
        let family = request.font.terminalFamily
        guard let font = Self.font(family, like: TerminalProfiles.parentFont()) else {
            return .failed("\(family) has no upright face")
        }

        if isRunning, case let .failed(message) = await Self.run(Self.liveScript(font.fontName)) {
            return .failed(message)
        }
        guard !request.isPreview else { return .applied() }
        do {
            var profile = TerminalProfiles.vibeshedProfile()
                ?? TerminalTarget.baseProfile(parent: TerminalProfiles.parentProfile())
            profile["Font"] = try NSKeyedArchiver.archivedData(withRootObject: font, requiringSecureCoding: true)
            try TerminalProfiles.write(profile)
        } catch {
            return .failed("profile: \(error.localizedDescription)")
        }
        if request.config.terminalDefaultProfile {
            TerminalProfiles.setDefault(TerminalTarget.profileName)
        } else {
            TerminalProfiles.restoreDefault()
        }
        return .applied()
    }

    func snapshot(config _: ThemeConfig) async -> ThemeRestore? {
        guard ThemeApps.isRunning(Self.bundleID) else { return nil }
        let script = """
        set out to ""
        tell application id "\(Self.bundleID)"
            if exists settings set "\(TerminalTarget.profileName)" then
                set out to "profile|" & font name of settings set "\(TerminalTarget.profileName)" & linefeed
            end if
            repeat with w in windows
                try
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        set out to out & (id of w as string) & "|" & i & "|" & font name of t & linefeed
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
        guard let output = try? await AppleScriptRunner.run(script) else { return nil }

        // `profile|<font>`, then one line per tab: `<window id>|<tab index>|<font>`.
        var blocks: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let object: String
            if fields.count == 2, fields[0] == "profile" {
                object = "settings set \"\(TerminalTarget.profileName)\""
            } else if fields.count == 3 {
                object = "tab \(fields[1]) of window id \(fields[0])"
            } else {
                continue
            }
            blocks.append("""
            try
                set font name of \(object) to "\(fields[fields.count - 1].escapedForAppleScript)"
            end try
            """)
        }
        guard !blocks.isEmpty else { return nil }
        let restore = "tell application id \"\(Self.bundleID)\"\n\(blocks.joined(separator: "\n"))\nend tell"
        return { _ = try? await AppleScriptRunner.run(restore) }
    }

    /// `family` in the weight and size of `reference` (Terminal's default size without one).
    static func font(_ family: String, like reference: NSFont?) -> NSFont? {
        guard let face = FontFaces.face(of: family, like: reference?.fontName) else { return nil }
        return NSFont(name: face, size: reference?.pointSize ?? 11)
    }

    /// Sets the font name — sizes stay as they are — of the Vibeshed profile, if the
    /// running Terminal knows it, and of every tab.
    private static func liveScript(_ fontName: String) -> String {
        let name = fontName.escapedForAppleScript
        return """
        tell application id "\(bundleID)"
            if exists settings set "\(TerminalTarget.profileName)" then
                set font name of settings set "\(TerminalTarget.profileName)" to "\(name)"
            end if
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        set font name of t to "\(name)"
                    end repeat
                end try
            end repeat
        end tell
        """
    }

    private static func run(_ script: String) async -> ThemeTargetOutcome {
        do {
            try await AppleScriptRunner.run(script, timeout: 10)
            return .applied()
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
