import Foundation

struct JetBrainsConfig: Codable, Sendable, Equatable {
    /// Maximum number of recent projects to show (1–100).
    var maxResults: Int = 20

    /// Set of action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    /// Filter to specific IDE tags (nil = all detected).
    /// Tags: "idea", "pycharm", "webstorm", "datagrip", "goland",
    /// "rustrover", "clion", "rider", "phpstorm", "rubymine", "studio".
    var enabledIDEs: Set<String>?
}
