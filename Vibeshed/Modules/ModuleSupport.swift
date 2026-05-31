import Foundation

// Small shared helpers used across modules. Previously these were copy-pasted into
// nearly every module (abbreviatePath ×8, a djb2 hash ×8, the rank formula ×7).

/// Abbreviates a home-relative absolute path to use `~`.
func abbreviatePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path.hasPrefix(home) {
        return "~" + path.dropFirst(home.count)
    }
    return path
}

/// A monotonically decreasing relevance score for the `index`-th item in an
/// already-ranked list (most-recent / most-relevant first). Caps at a 0.3 floor so
/// long lists still surface in fuzzy search. `step` controls the decay per position.
func rankedScore(index: Int, step: Double = 0.02) -> Double {
    max(0.3, 0.95 - Double(index) * step)
}

/// A simple time-to-live cache for a single value. Returns `nil` once the stored
/// value is older than `ttl`, prompting the caller to recompute and `store` again.
struct TimedCache<Value> {
    private let ttl: TimeInterval
    private var stored: Value?
    private var timestamp: Date = .distantPast

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    /// The cached value, or `nil` if absent or stale.
    var value: Value? {
        guard stored != nil, Date().timeIntervalSince(timestamp) <= ttl else {
            return nil
        }
        return stored
    }

    mutating func store(_ value: Value) {
        stored = value
        timestamp = Date()
    }

    mutating func invalidate() {
        stored = nil
        timestamp = .distantPast
    }
}

/// Stable, process-independent identifiers for action IDs.
///
/// Uses djb2 over UTF-8 bytes rather than `Hasher`, because `Hasher` is seeded
/// per-process and would produce different IDs on every launch — these IDs must be
/// stable across launches so usage tracking and selection survive a restart.
enum StableID {
    static func hash(_ input: String) -> String {
        var hash: UInt64 = 5381
        for byte in input.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 36)
    }
}
