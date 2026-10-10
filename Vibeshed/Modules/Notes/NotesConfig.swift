import Foundation

struct NotesConfig: Codable, Sendable, Equatable {
    /// The most recently edited notes listed in the main search; 0 lists none.
    /// Search Notes always covers every note.
    var maxResults = 100

    /// Search Notes matches the text of notes as well as their titles.
    var searchContent = true

    /// Folder new notes go in; nil = the default folder of Notes' default account.
    var newNoteFolder: String?

    /// Action name suffixes to expose (nil = all).
    var enabledActions: Set<String>?

    init() {}

    /// Decodes each field leniently: Codable synthesis ignores Swift property
    /// defaults, and a user's section may specify only some keys.
    init(from decoder: Decoder) throws {
        let defaults = NotesConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults) ?? defaults.maxResults
        searchContent = try container.decodeIfPresent(Bool.self, forKey: .searchContent) ?? defaults.searchContent
        newNoteFolder = try container.decodeIfPresent(String.self, forKey: .newNoteFolder)
        enabledActions = try container.decodeIfPresent(Set<String>.self, forKey: .enabledActions)
    }

    private enum CodingKeys: String, CodingKey {
        case maxResults
        case searchContent
        case newNoteFolder
        case enabledActions
    }
}
