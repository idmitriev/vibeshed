import Foundation

struct EmojiConfig: Codable, Sendable, Equatable {
    /// Most emoji listed while picking one for `emoji/find`.
    var maxResults: Int = 50
    var pasteOnSelect: Bool = false

    init() {}

    // Codable synthesis ignores Swift property defaults, so decode each field
    // leniently — a user's section may specify only some keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? 50
        pasteOnSelect = try container.decodeIfPresent(Bool.self, forKey: .pasteOnSelect) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case maxResults
        case pasteOnSelect
    }
}
