@testable import Vibeshed
import XCTest

@MainActor
final class UsageTrackerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testSaveLoadRoundTripPreservesCountsAndDates() throws {
        let url = dir.appendingPathComponent("usage.json")

        let tracker = UsageTracker(storageURL: url)
        tracker.recordUsage(actionID: ActionID(module: "system", name: "lock"))
        tracker.recordUsage(actionID: ActionID(module: "system", name: "lock"))
        tracker.recordUsage(actionID: ActionID(module: "audio", name: "mute"))
        tracker.save()

        let reloaded = UsageTracker(storageURL: url)
        XCTAssertEqual(reloaded.usageCounts["system/lock"], 2)
        XCTAssertEqual(reloaded.usageCounts["audio/mute"], 1)
        XCTAssertNotNil(reloaded.lastUsedDates["system/lock"], "dates must survive a reload")
    }

    func testQueryHistorySurvivesAReload() {
        let url = dir.appendingPathComponent("usage.json")
        let tracker = UsageTracker(storageURL: url)
        tracker.recordUsage(actionID: ActionID("theme/switch"), query: "theme")
        tracker.save()

        // Dates are stored to the second, so compare weights.
        let reloaded = UsageTracker(storageURL: url)
        XCTAssertEqual(reloaded.queryHistory.picks.mapValues { $0.mapValues(\.weight) }, ["theme/switch": ["theme": 1]])
        let affinity = reloaded.makeScoringContext(query: "the").queryAffinity["theme/switch"]
        XCTAssertEqual(affinity ?? -1, 0.5, accuracy: 0.001)
    }

    /// A file from before query history keeps its counts rather than failing to decode.
    func testLoadsUsageSavedBeforeQueryHistory() throws {
        let url = dir.appendingPathComponent("usage.json")
        let legacy = #"{"counts":{"system/lock":3},"lastUsed":{"system/lock":"2026-10-01T09:00:00Z"}}"#
        try Data(legacy.utf8).write(to: url)

        let tracker = UsageTracker(storageURL: url)
        XCTAssertEqual(tracker.usageCounts["system/lock"], 3)
        XCTAssertEqual(tracker.queryHistory, QueryHistory())
    }
}
