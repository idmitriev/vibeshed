import Foundation
import OSLog

actor EmojiModule: ModuleConfigurable {
    let id = "emoji"
    let displayName = "Emoji"
    let iconName = "face.smiling"
    var isEnabled = true

    typealias Config = EmojiConfig
    static var defaultConfig: Config? {
        .init()
    }

    /// Emoji matches are computed from the query text, so the picker re-queries
    /// this module on every keystroke instead of serving ~1,900 emoji from the
    /// corpus cache (which would also flood the empty-query view).
    static let isQueryDependent = true

    private var config: EmojiConfig = .init()
    private let log = Log.module("emoji")

    func initialize(context: ModuleContext) async throws {
        log.info("Emoji module initialized (\(EmojiCatalog.entries.count, privacy: .public) emoji)")
    }

    func configDidUpdate(_ config: EmojiConfig) async {
        self.config = config
        log.debug("Config updated")
    }

    static func validate(_ config: EmojiConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.maxResults < 1 || config.maxResults > 50 {
            errors.append("maxResults must be between 1 and 50")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count >= 2 else { return [] }
        let tokens = trimmed.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }

        var scored: [(index: Int, entry: EmojiEntry, score: Double)] = []
        for (index, entry) in EmojiCatalog.entries.enumerated() {
            if let score = Self.matchScore(entry: entry, tokens: tokens) {
                scored.append((index, entry, score))
            }
        }
        // Tiebreak on catalog index: emoji-test.txt order groups related emoji sensibly.
        let top = scored
            .sorted { ($0.score, $1.index) > ($1.score, $0.index) }
            .prefix(config.maxResults)

        let paste = config.pasteOnSelect
        return top.map { buildAction(for: $0.entry, query: trimmed, pasteOnSelect: paste) }
    }

    /// Emoji IDs are cheaply reversible ("emoji/copy.<slug>" → catalog entry), so
    /// resolve directly instead of the default empty-query `provideActions` scan
    /// (which returns nothing for this query-dependent module). This makes emoji
    /// actions usable from keybindings, aliases, and vibeshed:// URIs.
    func action(id: ActionID) async -> (any Action)? {
        guard id.moduleID == self.id, id.actionName.hasPrefix("copy.") else { return nil }
        let slug = String(id.actionName.dropFirst("copy.".count))
        guard let entry = EmojiCatalog.entries.first(where: {
            $0.name.replacingOccurrences(of: " ", with: "-") == slug
        }) else { return nil }
        return buildAction(for: entry, query: entry.name, pasteOnSelect: config.pasteOnSelect)
    }

    // MARK: - Matching

    /// Every token must match the name or a keyword; returns nil otherwise.
    /// Name matches outrank keyword matches, prefixes outrank substrings.
    static func matchScore(entry: EmojiEntry, tokens: [String]) -> Double? {
        var total = 0.0
        for token in tokens {
            var best = 0.0
            if entry.name.hasPrefix(token) {
                best = 1.0
            } else if entry.name.contains(token) {
                best = 0.7
            }
            if best < 0.6, entry.keywords.contains(where: { $0.hasPrefix(token) }) {
                best = 0.6
            } else if best < 0.4, entry.keywords.contains(where: { $0.contains(token) }) {
                best = 0.4
            }
            guard best > 0 else { return nil }
            total += best
        }
        return total / Double(tokens.count)
    }

    // MARK: - Action Building

    private func buildAction(
        for entry: EmojiEntry,
        query: String,
        pasteOnSelect: Bool
    ) -> EmojiAction {
        let char = entry.char
        let slug = entry.name.replacingOccurrences(of: " ", with: "-")
        return EmojiAction(
            id: ActionID(module: "emoji", name: "copy.\(slug)"),
            title: "\(char)  \(entry.name.capitalized)",
            subtitle: pasteOnSelect ? "Paste emoji" : "Copy emoji to clipboard",
            iconName: "face.smiling",
            keywords: [query, "emoji", entry.name] + entry.keywords
        ) { _ in
            await MainActor.run {
                ClipboardManager.writeToPasteboard(char)
                if pasteOnSelect {
                    ClipboardManager.pasteFromPasteboard()
                }
            }
            return .dismiss
        }
    }
}
