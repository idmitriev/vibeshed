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
        if config.maxResults < 1 || config.maxResults > 200 {
            errors.append("maxResults must be between 1 and 200")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    /// Individual emoji are only offered as options of `emoji/find`, not as
    /// top-level results, so they don't crowd out everything else in search.
    func provideActions(query: String, scoring: ScoringContext) async -> [any Action] {
        [buildFindAction()]
    }

    func provideParameterOptions(
        for parameterID: String,
        in actionID: ActionID,
        query: String
    ) async -> [ParameterOption] {
        guard parameterID == "emoji" else { return [] }
        return Self.search(query: query, limit: config.maxResults).map { entry in
            ParameterOption(
                id: entry.char,
                label: "\(entry.char)  \(entry.name.capitalized)",
                subtitle: entry.keywords.isEmpty ? nil : entry.keywords.joined(separator: ", ")
            )
        }
    }

    /// Emoji IDs are cheaply reversible ("emoji/copy.<slug>" → catalog entry), so
    /// resolve directly instead of the default `provideActions` scan (which only
    /// holds `emoji/find`). This keeps single-emoji actions usable from
    /// keybindings, aliases, and vibeshed:// URIs.
    func action(id: ActionID) async -> (any Action)? {
        guard id.moduleID == self.id else { return nil }
        if id.actionName == "find" { return buildFindAction() }
        guard id.actionName.hasPrefix("copy.") else { return nil }
        let slug = String(id.actionName.dropFirst("copy.".count))
        guard let entry = EmojiCatalog.entries.first(where: {
            $0.name.replacingOccurrences(of: " ", with: "-") == slug
        }) else { return nil }
        return buildCopyAction(for: entry)
    }

    // MARK: - Matching

    /// Catalog entries matching every query token, best first; an empty query lists
    /// the catalog in order (emoji-test.txt order groups related emoji sensibly).
    static func search(query: String, limit: Int) -> [EmojiEntry] {
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return Array(EmojiCatalog.entries.prefix(limit)) }

        var scored: [(index: Int, entry: EmojiEntry, score: Double)] = []
        for (index, entry) in EmojiCatalog.entries.enumerated() {
            if let score = matchScore(entry: entry, tokens: tokens) {
                scored.append((index, entry, score))
            }
        }
        // Tiebreak on catalog index.
        return scored
            .sorted { ($0.score, $1.index) > ($1.score, $0.index) }
            .prefix(limit)
            .map(\.entry)
    }

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

    private func buildFindAction() -> EmojiAction {
        let pasteOnSelect = config.pasteOnSelect
        return EmojiAction(
            id: ActionID(module: "emoji", name: "find"),
            title: "Find Emoji",
            subtitle: pasteOnSelect ? "Search and paste an emoji" : "Search and copy an emoji",
            iconName: "face.smiling",
            relevanceScore: 0.7,
            keywords: ["emoji", "emoticon", "smiley", "find", "search", "insert", "symbol"],
            parameters: [
                ActionParameter(
                    id: "emoji",
                    label: "Emoji",
                    type: .dynamicSelection(hint: "emoji"),
                    isRequired: true,
                    filtersOwnOptions: true
                ),
            ]
        ) { values in
            guard let char = values["emoji"], !char.isEmpty else {
                return .showResult(title: "Error", body: "No emoji selected")
            }
            await Self.deliver(char, pasteOnSelect: pasteOnSelect)
            return .dismiss
        }
    }

    private func buildCopyAction(for entry: EmojiEntry) -> EmojiAction {
        let char = entry.char
        let pasteOnSelect = config.pasteOnSelect
        let slug = entry.name.replacingOccurrences(of: " ", with: "-")
        return EmojiAction(
            id: ActionID(module: "emoji", name: "copy.\(slug)"),
            title: "\(char)  \(entry.name.capitalized)",
            subtitle: pasteOnSelect ? "Paste emoji" : "Copy emoji to clipboard",
            iconName: "face.smiling",
            keywords: ["emoji", entry.name] + entry.keywords
        ) { _ in
            await Self.deliver(char, pasteOnSelect: pasteOnSelect)
            return .dismiss
        }
    }

    private static func deliver(_ char: String, pasteOnSelect: Bool) async {
        await MainActor.run {
            ClipboardManager.writeToPasteboard(char)
            if pasteOnSelect {
                ClipboardManager.pasteFromPasteboard()
            }
        }
    }
}
