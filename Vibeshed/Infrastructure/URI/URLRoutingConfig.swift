import Foundation

struct URLRoutingRule: Codable, Sendable, Equatable {
    let pattern: String
    let browser: String?
    let profile: String?
    let action: String?
}

struct URLRoutingConfig: Codable, Sendable, Equatable {
    var rules: [URLRoutingRule] = []
    var defaultBrowser: String?
    var defaultProfile: String?
    var registerAsDefaultBrowser: Bool = true
}
