import Foundation

struct VSCodeConfig: Codable, Sendable, Equatable {
    /// Maximum number of recent projects to show (1–100).
    var maxResults: Int = 20

    /// Whether to show individual recently opened files (not folders).
    var showFiles: Bool = false

    /// Whether to show remote projects (SSH, WSL, etc.).
    var showRemote: Bool = false

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Custom path to the VSCode `code` CLI binary.
    /// Defaults to searching common locations.
    var codePath: String?

    /// Additional VSCode variants to scan.
    /// Each entry maps a display name to an Application Support subdirectory.
    /// Built-in: "Code" (standard VSCode).
    var variants: [String: String]?
}
