import Foundation

struct WebSearchConfig: Codable, Sendable, Equatable {
    struct Engine: Codable, Sendable, Equatable {
        var name: String
        var urlTemplate: String
        var iconName: String?
    }

    var engines: [Engine] = Self.defaultEngines
    var minQueryLength: Int = 2

    static let defaultEngines: [Engine] = [
        Engine(
            name: "Google",
            urlTemplate: "https://www.google.com/search?q={query}",
            iconName: nil
        ),
        Engine(
            name: "DuckDuckGo",
            urlTemplate: "https://duckduckgo.com/?q={query}",
            iconName: nil
        ),
    ]

    init() {}

    // Codable synthesis ignores Swift property defaults, so decode each field
    // leniently — a user's section may specify only some keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engines = try container.decodeIfPresent([Engine].self, forKey: .engines)
            ?? Self.defaultEngines
        minQueryLength = try container.decodeIfPresent(Int.self, forKey: .minQueryLength) ?? 2
    }

    private enum CodingKeys: String, CodingKey {
        case engines
        case minQueryLength
    }
}
