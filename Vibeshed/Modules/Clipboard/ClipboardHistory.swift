import Foundation
import OSLog

enum ClipboardContentType: String, Codable, Sendable {
    case text
    case url
    case filePath
}

struct ClipboardItem: Codable, Sendable, Identifiable {
    let id: String
    let content: String
    let contentType: ClipboardContentType
    var timestamp: Date
    var sourceApp: String?
}

@MainActor
@Observable
final class ClipboardHistory {
    private(set) var items: [ClipboardItem] = []

    private let storageURL: URL
    private var saveWorkItem: DispatchWorkItem?
    private var maxItems: Int = 100
    private var excludeRegexes: [NSRegularExpression] = []

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        storageURL = home.appendingPathComponent(".config/vibeshed/clipboard.json")
        load()
    }

    func updateConfig(maxItems: Int, excludePatterns: [String]?) {
        self.maxItems = maxItems
        excludeRegexes = (excludePatterns ?? []).compactMap { pattern in
            do {
                return try NSRegularExpression(pattern: pattern)
            } catch {
                Log.module("clipboard").warning("Invalid exclude regex '\(pattern)': \(error.localizedDescription)")
                return nil
            }
        }
        trimToMax()
    }

    func addItem(content: String, sourceApp: String?) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isExcluded(trimmed) else { return }

        let itemID = stableHash(trimmed)

        // Dedup: remove existing entry with same content
        items.removeAll { $0.id == itemID }

        let item = ClipboardItem(
            id: itemID,
            content: trimmed,
            contentType: detectContentType(trimmed),
            timestamp: Date(),
            sourceApp: sourceApp
        )
        items.insert(item, at: 0)
        trimToMax()
        scheduleSave()
    }

    func clear() {
        items.removeAll()
        scheduleSave()
    }

    func removeItem(id: String) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: - Content Type Detection

    private func detectContentType(_ content: String) -> ClipboardContentType {
        if content.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://"#, options: .regularExpression) != nil {
            return .url
        }
        if !content.contains("\n"), content.hasPrefix("/") || content.hasPrefix("~/") {
            return .filePath
        }
        return .text
    }

    // MARK: - Exclusion

    private func isExcluded(_ content: String) -> Bool {
        let range = NSRange(content.startIndex..., in: content)
        return excludeRegexes.contains { regex in
            regex.firstMatch(in: content, range: range) != nil
        }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode(StoredHistory.self, from: data)
            items = stored.items
            Log.modules.info("Loaded clipboard history: \(self.items.count) items")
        } catch {
            Log.modules.error("Failed to load clipboard history: \(error.localizedDescription)")
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
        let stored = StoredHistory(items: items)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(stored)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.modules.error("Failed to save clipboard history: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private func trimToMax() {
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }

    private func stableHash(_ content: String) -> String {
        var hasher = Hasher()
        hasher.combine(content)
        let hash = hasher.finalize()
        return String(format: "%08x", abs(hash))
    }
}

// MARK: - Storage format

private struct StoredHistory: Codable {
    let items: [ClipboardItem]
}
