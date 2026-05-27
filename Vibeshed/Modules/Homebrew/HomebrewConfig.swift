import Foundation

struct HomebrewConfig: Codable, Sendable, Equatable {
    var brewPath: String = "/opt/homebrew/bin/brew"
    var enabledActions: Set<String>?
}
