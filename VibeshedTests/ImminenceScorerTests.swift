@testable import Vibeshed
import XCTest

final class ImminenceScorerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func boost(startsInMinutes: Double, durationMinutes: Double = 30) -> Double {
        let start = now.addingTimeInterval(startsInMinutes * 60)
        return ImminenceScorer.boost(
            scheduledStart: start,
            scheduledEnd: start.addingTimeInterval(durationMinutes * 60),
            now: now
        )
    }

    func testActionWithoutScheduleGetsNoBoost() {
        XCTAssertEqual(
            ImminenceScorer.boost(scheduledStart: nil, scheduledEnd: nil, now: now), 0
        )
    }

    func testStartingWithinPeakWindowGetsFullBoost() {
        XCTAssertEqual(boost(startsInMinutes: 0.5), ImminenceScorer.maxBoost)
        XCTAssertEqual(boost(startsInMinutes: 5), ImminenceScorer.maxBoost)
    }

    func testBoostDecaysWithDistanceToStart() {
        let soon = boost(startsInMinutes: 10)
        let later = boost(startsInMinutes: 45)
        let muchLater = boost(startsInMinutes: 100)

        XCTAssertLessThan(soon, ImminenceScorer.maxBoost)
        XCTAssertGreaterThan(soon, later)
        XCTAssertGreaterThan(later, muchLater)
        XCTAssertGreaterThan(muchLater, 0)
    }

    func testBeyondHorizonGetsNoBoost() {
        XCTAssertEqual(boost(startsInMinutes: 120), 0)
        XCTAssertEqual(boost(startsInMinutes: 600), 0)
    }

    func testJustStartedKeepsFullBoost() {
        XCTAssertEqual(boost(startsInMinutes: -10, durationMinutes: 60), ImminenceScorer.maxBoost)
    }

    func testLongRunningEventFallsBackToPlateau() {
        let value = boost(startsInMinutes: -90, durationMinutes: 180)
        XCTAssertEqual(value, ImminenceScorer.maxBoost * ImminenceScorer.underwayPlateau)
    }

    func testEndedEventGetsNoBoost() {
        XCTAssertEqual(boost(startsInMinutes: -45, durationMinutes: 30), 0)
    }

    func testStartedEventWithoutEndDateStopsBoostingOnceStale() {
        let recent = ImminenceScorer.boost(
            scheduledStart: now.addingTimeInterval(-2 * 60), scheduledEnd: nil, now: now
        )
        let stale = ImminenceScorer.boost(
            scheduledStart: now.addingTimeInterval(-90 * 60), scheduledEnd: nil, now: now
        )
        XCTAssertEqual(recent, ImminenceScorer.maxBoost)
        XCTAssertEqual(stale, 0)
    }
}
