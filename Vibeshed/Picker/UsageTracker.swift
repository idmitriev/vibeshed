import Foundation

@MainActor
@Observable
final class UsageTracker {
    private(set) var usageCounts: [String: Int] = [:]
    private(set) var lastUsedDates: [String: Date] = [:]
    private(set) var queryHistory = QueryHistory()

    private let storageURL: URL
    private var saveTask: Task<Void, Never>?

    init(storageURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.storageURL = storageURL ?? home
            .appendingPathComponent(".config/vibeshed/usage.json")
        load()
    }

    /// `query` is what was typed in the search field when the action was picked from
    /// the list; nil when it ran some other way (a chain, a pushed list).
    func recordUsage(actionID: ActionID, query: String? = nil, at now: Date = Date()) {
        let key = actionID.rawValue
        usageCounts[key, default: 0] += 1
        lastUsedDates[key] = now
        if let query {
            queryHistory.record(query: query, actionID: key, at: now)
        }
        scheduleSave()
    }

    func makeScoringContext(query: String, systemContext: SystemContext? = nil) -> ScoringContext {
        var context = ScoringContext(
            usageCounts: usageCounts,
            lastUsedDates: lastUsedDates,
            query: query,
            systemContext: systemContext
        )
        context.queryAffinity = queryHistory.shares(for: query, now: context.now)
        return context
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode(StoredUsage.self, from: data)
            usageCounts = stored.counts
            lastUsedDates = stored.lastUsed
            queryHistory = stored.queries ?? QueryHistory()
            Log.picker.info("Loaded usage data: \(self.usageCounts.count, privacy: .public) actions tracked")
        } catch {
            Log.picker.error("Failed to load usage data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        let stored = StoredUsage(
            counts: usageCounts, lastUsed: lastUsedDates, queries: queryHistory.pruned(at: Date())
        )
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(stored)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.picker.error("Failed to save usage data: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Storage format

private struct StoredUsage: Codable {
    let counts: [String: Int]
    let lastUsed: [String: Date]
    /// Optional: files written before query history existed don't have it.
    let queries: QueryHistory?
}
