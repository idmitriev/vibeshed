import Foundation

struct JetBrainsConfig: Codable, Sendable, Equatable {
    var maxResults: Int = 20
    var enabledActions: Set<String>?
    var enabledIDEs: Set<String>?
    var openInNewWindow: Bool = false
}
