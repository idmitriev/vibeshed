import Foundation
import XCTest

@testable import Vibeshed

final class ModuleSupportTests: XCTestCase {
    // MARK: - StableID

    func testStableIDIsDeterministic() {
        XCTAssertEqual(StableID.hash("/Users/me/proj"), StableID.hash("/Users/me/proj"))
    }

    func testStableIDDiffersForDifferentInput() {
        XCTAssertNotEqual(StableID.hash("a"), StableID.hash("b"))
    }

    func testStableIDKnownValue() {
        // djb2 seed 5381 with no bytes, base-36 encoded — pins the algorithm so a
        // refactor can't silently change IDs (which would break usage tracking).
        XCTAssertEqual(StableID.hash(""), "45h")
    }

    // MARK: - rankedScore

    func testRankedScoreDecreasesWithIndex() {
        XCTAssertEqual(rankedScore(index: 0), 0.95, accuracy: 0.0001)
        XCTAssertGreaterThan(rankedScore(index: 0), rankedScore(index: 5))
    }

    func testRankedScoreFloor() {
        XCTAssertEqual(rankedScore(index: 1000), 0.3, accuracy: 0.0001)
    }

    // MARK: - abbreviatePath

    func testAbbreviatesHomeRelativePath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(abbreviatePath(home + "/Projects/x"), "~/Projects/x")
    }

    func testLeavesNonHomePathUnchanged() {
        XCTAssertEqual(abbreviatePath("/opt/tools/bin"), "/opt/tools/bin")
    }
}
