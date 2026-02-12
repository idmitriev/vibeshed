import Foundation

struct SystemConfig: Codable, Sendable, Equatable {
    var screenshotPath: String = "~/Desktop"
    var enabledActions: Set<String>?
}
