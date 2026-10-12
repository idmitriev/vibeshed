import Foundation

struct ApplicationConfig: Codable, Sendable, Equatable {
    var showRunningOnly: Bool = false
    var excludedBundleIDs: [String] = []
    var cacheTTLSeconds: Double = 3
}

extension ApplicationConfig {
    /// Every key is optional, so a section sets only what it changes. A property's `=`
    /// default doesn't do that on its own: synthesized Decodable throws keyNotFound, and
    /// `ModuleConfigDecoder` then drops the whole section for the defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        showRunningOnly = try container.decodeIfPresent(Bool.self, forKey: .showRunningOnly)
            ?? defaults.showRunningOnly
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs)
            ?? defaults.excludedBundleIDs
        cacheTTLSeconds = try container.decodeIfPresent(Double.self, forKey: .cacheTTLSeconds)
            ?? defaults.cacheTTLSeconds
    }
}
