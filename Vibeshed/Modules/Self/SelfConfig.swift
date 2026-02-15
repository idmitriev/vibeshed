import Foundation

struct SelfConfig: Codable, Sendable, Equatable {
    var enabledActions: Set<String>?
}
