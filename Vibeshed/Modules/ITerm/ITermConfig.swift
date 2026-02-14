import Foundation

struct ITermConfig: Codable, Sendable, Equatable {
    /// Maximum number of sessions to show in results (1–50).
    var maxResults: Int = 20

    /// Whether to show the current working directory in session subtitles.
    var showCWD: Bool = true

    /// Whether to show session job name (e.g. "vim", "ssh") in results.
    var showJobName: Bool = true

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Predefined commands that appear as quick-run actions.
    /// Each entry maps a display name to a shell command string.
    var commands: [String: String]?

    /// Default profile name for new tabs/windows (nil = default profile).
    var defaultProfile: String?
}
