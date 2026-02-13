import Foundation

struct ClipboardConfig: Codable, Sendable, Equatable {
    var maxItems: Int = 100
    var pollingInterval: Double = 0.5
    var excludePatterns: [String]?
    var showClearAction: Bool = true
    var pasteOnSelect: Bool = true
    var enabledActions: Set<String>?
}
