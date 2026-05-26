import Foundation

struct ZedConfig: Codable, Sendable, Equatable {
    var maxResults: Int = 20
    var showRemote: Bool = false
    var enabledActions: Set<String>?
    var zedPath: String?
}
