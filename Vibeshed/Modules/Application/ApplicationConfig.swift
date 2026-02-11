import Foundation

struct ApplicationConfig: Codable, Sendable, Equatable {
    var showRunningOnly: Bool = false
    var excludedBundleIDs: [String] = []
}
