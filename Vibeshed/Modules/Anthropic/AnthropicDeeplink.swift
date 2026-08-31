import Foundation

/// `claude://` deeplinks handled by Claude Desktop.
///
/// The paths and parameter names below are the ones Claude Desktop's URL handler
/// accepts; it registers the `claude` scheme and drives its own OS launcher entries
/// (Dock menu, Spotlight actions) through the same URLs.
enum AnthropicDeeplink {
    static let bundleID = "com.anthropic.claudefordesktop"

    /// Marks the link as coming from an external launcher rather than in-app UI.
    private static let source = "vibeshed"

    static var isInstalled: Bool {
        AILaunch.isAppInstalled(bundleID: bundleID)
    }

    /// A new Claude Code session in the desktop app, optionally seeded with a prompt
    /// and a working folder.
    static func newCodeSession(prompt: String?, folder: String?) -> String? {
        AILaunch.url(
            "claude://code/new",
            query: ["q": prompt, "folder": folder, "source": source]
        )
    }

    /// Reopens a Claude Code session already known to the desktop app. `session` is a
    /// desktop-side `local_…` identifier, or `last` for the most recent session.
    static func continueCodeSession(_ session: String) -> String? {
        AILaunch.url(
            "claude://code/continue",
            query: ["session": session, "source": source]
        )
    }

    /// The most recently active Claude Code session.
    static var continueLast: String? {
        continueCodeSession("last")
    }

    /// Jumps to the session that has been waiting longest for a permission answer.
    static var needsInput: String? {
        AILaunch.url("claude://code/needs-input", query: ["source": source])
    }

    /// Imports a CLI session into the desktop app by its CLI-side UUID, letting a
    /// terminal session continue in the GUI.
    static func resumeCLISession(_ sessionID: String) -> String? {
        guard isCLISessionID(sessionID) else { return nil }
        return AILaunch.url("claude://resume", query: ["session": sessionID])
    }

    /// A new (non-code) Claude chat, optionally seeded with a prompt.
    static func newChat(prompt: String?) -> String? {
        AILaunch.url("claude://new", query: ["q": prompt, "source": source])
    }

    // MARK: - Identifier shapes

    /// Claude Code CLI session IDs are plain UUIDs; the desktop handler rejects
    /// anything else on `claude://resume`.
    static func isCLISessionID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    /// Desktop-side session IDs are `local_` followed by a UUID.
    static func isDesktopSessionID(_ value: String) -> Bool {
        value.hasPrefix("local_")
            && isCLISessionID(String(value.dropFirst("local_".count)))
    }
}
