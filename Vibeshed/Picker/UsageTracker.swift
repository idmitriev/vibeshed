import Foundation

@MainActor
@Observable
final class UsageTracker {
    private(set) var usageCounts: [String: Int] = [:]
    private(set) var lastUsedDates: [String: Date] = [:]

    private let storageURL: URL
    private var saveWorkItem: DispatchWorkItem?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        storageURL = home
            .appendingPathComponent(".config/vibeshed/usage.json")
        load()
    }

    func recordUsage(actionID: ActionID) {
        let key = actionID.rawValue
        usageCounts[key, default: 0] += 1
        lastUsedDates[key] = Date()
        scheduleSave()
    }

    func makeScoringContext(query: String, systemContext: SystemContext? = nil) -> ScoringContext {
        ScoringContext(
            usageCounts: usageCounts,
            lastUsedDates: lastUsedDates,
            query: query,
            systemContext: systemContext
        )
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let stored = try JSONDecoder().decode(StoredUsage.self, from: data)
            usageCounts = stored.counts
            lastUsedDates = stored.lastUsed
            Log.picker.info("Loaded usage data: \(self.usageCounts.count) actions tracked")
        } catch {
            Log.picker.error("Failed to load usage data: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.save()
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func save() {
        let stored = StoredUsage(counts: usageCounts, lastUsed: lastUsedDates)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(stored)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.picker.error("Failed to save usage data: \(error.localizedDescription)")
        }
    }
}

// MARK: - Storage format

private struct StoredUsage: Codable {
    let counts: [String: Int]
    let lastUsed: [String: Date]
}
