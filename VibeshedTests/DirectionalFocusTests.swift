import CoreGraphics
@testable import Vibeshed
import XCTest

/// Frames are top-left origin, on a 2000×1200 screen split into tiles with 4pt gaps.
final class DirectionalFocusTests: XCTestCase {
    private let left = window(1, x: 4, y: 4, width: 994, height: 1192)
    private let right = window(2, x: 1002, y: 4, width: 994, height: 1192)
    private let topRight = window(3, x: 1002, y: 4, width: 994, height: 594)
    private let bottomRight = window(4, x: 1002, y: 602, width: 994, height: 594)

    func testFocusesTheTileBeside() {
        XCTAssertEqual(target(from: left, .right, among: [left, right])?.id, 2)
        XCTAssertEqual(target(from: right, .left, among: [left, right])?.id, 1)
        XCTAssertNil(target(from: left, .left, among: [left, right]))
        XCTAssertNil(target(from: left, .up, among: [left, right]))
    }

    /// From the top right tile, down is the tile below, not the full-height left one
    /// whose center happens to sit lower.
    func testPrefersTheTileInLineOverOneDiagonallyOff() {
        let windows = [topRight, bottomRight, left]
        XCTAssertEqual(target(from: topRight, .down, among: windows)?.id, 4)
        XCTAssertEqual(target(from: bottomRight, .up, among: windows)?.id, 3)
        XCTAssertEqual(target(from: topRight, .left, among: windows)?.id, 1)
    }

    /// Several windows in one tile: the frontmost one, which is the one you see.
    func testTakesTheFrontmostOfAStack() {
        let behind = window(5, x: 1002, y: 4, width: 994, height: 1192)
        XCTAssertEqual(target(from: left, .right, among: [right, left, behind])?.id, 2)
        XCTAssertEqual(target(from: left, .right, among: [behind, left, right])?.id, 5)
    }

    func testNearestEdgeWins() {
        let near = window(6, x: 1100, y: 100, width: 300, height: 300)
        let far = window(7, x: 1600, y: 100, width: 300, height: 300)
        XCTAssertEqual(target(from: left, .right, among: [far, near])?.id, 6)
    }

    /// Overlapping floating windows: nothing lies wholly to the side, so a center that
    /// does is enough.
    func testFallsBackToCentersForOverlappingWindows() {
        let focused = window(8, x: 500, y: 200, width: 800, height: 600)
        let overlapping = window(9, x: 200, y: 300, width: 800, height: 600)
        XCTAssertEqual(target(from: focused, .left, among: [focused, overlapping])?.id, 9)
        XCTAssertNil(target(from: focused, .right, among: [focused, overlapping]))
    }

    func testSkipsSlivers() {
        let sliver = window(10, x: 1500, y: 500, width: 20, height: 20)
        XCTAssertNil(target(from: left, .right, among: [left, sliver]))
    }

    /// A second display to the right is just further along.
    func testCrossesDisplays() {
        let otherDisplay = window(11, x: 2004, y: 100, width: 1000, height: 800)
        XCTAssertEqual(target(from: right, .right, among: [right, otherDisplay, left])?.id, 11)
        XCTAssertEqual(target(from: left, .right, among: [otherDisplay, right, left])?.id, 2)
    }

    // MARK: - Helpers

    private func target(
        from focused: WindowInfo,
        _ direction: DirectionalFocus.Direction,
        among windows: [WindowInfo]
    ) -> WindowInfo? {
        DirectionalFocus.target(from: focused, direction: direction, among: windows)
    }
}

private func window(_ id: Int, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> WindowInfo {
    let frame = CGRect(x: x, y: y, width: width, height: height)
    return WindowInfo(
        id: id, title: "", appName: "App", bundleID: nil, pid: 1,
        frame: frame, screenFrame: frame, isOnScreen: true, isMinimized: false
    )
}
