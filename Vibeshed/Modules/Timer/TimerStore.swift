import Foundation
import OSLog

enum TimerEntryType: String, Codable, Sendable {
    case timer
    case reminder
}

enum TimerEntryStatus: String, Codable, Sendable {
    case active
    case fired
    case cancelled
}

struct TimerEntry: Codable, Sendable, Identifiable {
    let id: String
    var label: String
    let fireDate: Date
    let createdDate: Date
    let type: TimerEntryType
    let duration: TimeInterval?
    let sound: String
    var status: TimerEntryStatus
}

@MainActor
@Observable
final class TimerStore {
    private(set) var items: [TimerEntry] = []

    private let storageURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private var maxActive: Int = 20

    var activeItems: [TimerEntry] {
        items.filter { $0.status == .active }
    }

    var firedItems: [TimerEntry] {
        items.filter { $0.status == .fired }
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        storageURL = home.appendingPathComponent(".config/vibeshed/timers.json")
        load()
        markOverdueAsFired()
    }

    func updateConfig(maxActive: Int) {
        self.maxActive = maxActive
    }

    @discardableResult
    func addTimer(
        duration: TimeInterval,
        label: String,
        sound: String
    ) -> TimerEntry? {
        guard activeItems.count < maxActive else { return nil }

        let entry = TimerEntry(
            id: UUID().uuidString,
            label: label,
            fireDate: Date().addingTimeInterval(duration),
            createdDate: Date(),
            type: .timer,
            duration: duration,
            sound: sound,
            status: .active
        )
        items.insert(entry, at: 0)
        scheduleSave()
        return entry
    }

    @discardableResult
    func addReminder(
        fireDate: Date,
        label: String,
        sound: String
    ) -> TimerEntry? {
        guard activeItems.count < maxActive else { return nil }

        let entry = TimerEntry(
            id: UUID().uuidString,
            label: label,
            fireDate: fireDate,
            createdDate: Date(),
            type: .reminder,
            duration: nil,
            sound: sound,
            status: .active
        )
        items.insert(entry, at: 0)
        scheduleSave()
        return entry
    }

    func cancel(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].status = .cancelled
        scheduleSave()
    }

    func markFired(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].status = .fired
        scheduleSave()
    }

    func removeCompleted() {
        items.removeAll { $0.status != .active }
        scheduleSave()
    }

    func cancelAll() {
        for index in items.indices where items[index].status == .active {
            items[index].status = .cancelled
        }
        scheduleSave()
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode(StoredTimers.self, from: data)
            items = stored.items
            Log.modules.info(
                "Loaded timer store: \(self.items.count, privacy: .public) items"
            )
        } catch {
            Log.modules.error(
                "Failed to load timer store: \(error.localizedDescription, privacy: .public)"
            )
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
        DispatchQueue.main.asyncAfter(
            deadline: .now() + 2.0,
            execute: workItem
        )
    }

    private func save() {
        let stored = StoredTimers(items: items)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(stored)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.modules.error(
                "Failed to save timer store: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func markOverdueAsFired() {
        let now = Date()
        var changed = false
        for index in items.indices
        where items[index].status == .active && items[index].fireDate <= now {
            items[index].status = .fired
            changed = true
        }
        if changed {
            scheduleSave()
        }
    }
}

// MARK: - Storage Format

private struct StoredTimers: Codable {
    let items: [TimerEntry]
}
