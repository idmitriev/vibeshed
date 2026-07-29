import Foundation

struct ProcessesConfig: Codable, Sendable, Equatable {
    var cacheTTLSeconds: Double = 2.0
    var maxResults: Int = 100
    var excludedNames: [String] = []
}
