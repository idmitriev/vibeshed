import Foundation

struct EmojiEntry: Sendable {
    let char: String
    let name: String
    let keywords: [String]
}

/// Parses the generated `EmojiData.tsv` once, on first access.
enum EmojiCatalog {
    static let entries: [EmojiEntry] = EmojiData.tsv
        .split(separator: "\n")
        .compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { return nil }
            let keywords = parts.count >= 3
                ? parts[2].split(separator: ",").map(String.init)
                : []
            return EmojiEntry(char: String(parts[0]), name: String(parts[1]), keywords: keywords)
        }
}
