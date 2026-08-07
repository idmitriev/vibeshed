@testable import Vibeshed
import XCTest

@MainActor
final class UsageTrackerTests: XCTestCase {
    func testSaveLoadRoundTripPreservesCountsAndDates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
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
}
