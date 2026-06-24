import Foundation

struct SettingsConfig: Codable, Sendable, Equatable {
    /// Restrict the offered panes to this set of pane IDs (e.g. `["wifi", "bluetooth"]`).
    /// `nil` means all catalog panes are available.
    var enabledPanes: Set<String>?
    /// Additional custom panes keyed by display title → pane target identifier.
    var customPanes: [String: String]?
}
