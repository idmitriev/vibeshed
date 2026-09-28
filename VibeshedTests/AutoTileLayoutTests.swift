@testable import Vibeshed
import XCTest
import Yams

/// Auto-tile's per-display layout rules: a display's only window fills it, from two
/// windows up each takes a grid cell, and `maximizeSingleWindow: false` keeps the grid
/// for a lone window too.
@MainActor
final class AutoTileLayoutTests: XCTestCase {
    private typealias Candidate = AutoTileLayout.Candidate
    private typealias Placement = AutoTileLayout.Placement

    /// Two equal columns on a 1000×800 area without a gap: left is x 0–500, right 500–1000.
    private let columns = DisplayGridConfig(match: nil, columns: [1, 1], rows: [1], padding: nil)
    private let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let somewhere = CGRect(x: 120, y: 90, width: 600, height: 400)

    private var left: CGRect {
        TilingGrid.cellRect(row: 0, col: 0, in: area, grid: columns)
    }

    private var right: CGRect {
        TilingGrid.cellRect(row: 0, col: 1, in: area, grid: columns)
    }

    private func plan(
        _ candidates: [Candidate],
        grid: DisplayGridConfig? = nil,
        maximizeSingleWindow: Bool = true
    ) -> [Placement] {
        AutoTileLayout.plan(
            candidates,
            grid: grid ?? columns,
            area: area,
            gap: 0,
            maximizeSingleWindow: maximizeSingleWindow
        )
    }

    // MARK: - One Window

    func testLoneArrivalFillsTheDisplay() {
        XCTAssertEqual(
            plan([Candidate(id: 1, frame: somewhere, reason: .arrived)]),
            [Placement(windowID: 1, slot: .maximized, frame: area)]
        )
    }

    func testLoneWindowAlreadyFillingTheDisplayIsLeftAlone() {
        let nearlyArea = area.insetBy(dx: 2, dy: 2)
        XCTAssertEqual(
            plan([Candidate(id: 1, frame: nearlyArea, reason: .moved)]),
            [Placement(windowID: 1, slot: .maximized, frame: nil)]
        )
    }

    /// Its neighbour closed, minimized, or left the display.
    func testWindowLeftAloneInACellIsMaximized() {
        XCTAssertEqual(
            plan([Candidate(id: 1, frame: left, reason: .unchanged)]),
            [Placement(windowID: 1, slot: .maximized, frame: area)]
        )
    }

    func testDraggedLoneWindowFillsTheDisplayAgain() {
        XCTAssertEqual(
            plan([Candidate(id: 1, frame: right, reason: .moved)]),
            [Placement(windowID: 1, slot: .maximized, frame: area)]
        )
    }

    func testLoneWindowTakesACellWhenMaximizeSingleWindowIsOff() {
        XCTAssertEqual(
            plan([Candidate(id: 1, frame: somewhere, reason: .arrived)], maximizeSingleWindow: false),
            [Placement(windowID: 1, slot: .cell(row: 0, col: 0), frame: left)]
        )
        XCTAssertEqual(
            plan([Candidate(id: 1, frame: right, reason: .unchanged)], maximizeSingleWindow: false),
            [Placement(windowID: 1, slot: .cell(row: 0, col: 1), frame: nil)]
        )
    }

    func testNoWindowsNoPlacements() {
        XCTAssertEqual(plan([]), [])
    }

    // MARK: - Leaving the Maximized Slot

    func testSecondWindowSplitsTheDisplay() {
        XCTAssertEqual(
            plan([
                Candidate(id: 2, frame: somewhere, reason: .arrived),
                Candidate(id: 1, frame: area, reason: .unchanged),
            ]),
            [
                Placement(windowID: 2, slot: .cell(row: 0, col: 1), frame: right),
                Placement(windowID: 1, slot: .cell(row: 0, col: 0), frame: left),
            ]
        )
    }

    /// Apps that size in steps (terminals, for one) can stop a few points short of the
    /// area; such a window still counts as filling the display.
    func testWindowHeldShortOfTheAreaStillLeavesIt() {
        let shortOfArea = CGRect(x: 0, y: 0, width: 993, height: 786)
        XCTAssertEqual(
            plan([
                Candidate(id: 1, frame: shortOfArea, reason: .unchanged),
                Candidate(id: 2, frame: somewhere, reason: .arrived),
            ]),
            [
                Placement(windowID: 1, slot: .cell(row: 0, col: 0), frame: left),
                Placement(windowID: 2, slot: .cell(row: 0, col: 1), frame: right),
            ]
        )
    }

    /// An app restoring a window straight into a cell keeps it there; the maximized
    /// window takes the other one.
    func testArrivalAlreadyInACellKeepsIt() {
        XCTAssertEqual(
            plan([
                Candidate(id: 2, frame: left, reason: .arrived),
                Candidate(id: 1, frame: area, reason: .unchanged),
            ]),
            [
                Placement(windowID: 2, slot: .cell(row: 0, col: 0), frame: nil),
                Placement(windowID: 1, slot: .cell(row: 0, col: 1), frame: right),
            ]
        )
    }

    /// A window dragged in from another display claims the cell it was dropped on first.
    func testDroppedWindowClaimsItsCellBeforeTheMaximizedOneMoves() {
        let droppedOnLeft = CGRect(x: 40, y: 60, width: 420, height: 500)
        XCTAssertEqual(
            plan([
                Candidate(id: 1, frame: area, reason: .unchanged),
                Candidate(id: 2, frame: droppedOnLeft, reason: .moved),
            ]),
            [
                Placement(windowID: 1, slot: .cell(row: 0, col: 1), frame: right),
                Placement(windowID: 2, slot: .cell(row: 0, col: 0), frame: left),
            ]
        )
    }

    func testMaximizedWindowShrinksIntoTheCellUnderItsCenter() {
        let thirds = DisplayGridConfig(match: nil, columns: [1, 2, 1], rows: [1], padding: nil)
        let placements = plan(
            [
                Candidate(id: 1, frame: area, reason: .unchanged),
                Candidate(id: 2, frame: somewhere, reason: .arrived),
            ],
            grid: thirds
        )
        XCTAssertEqual(placements.map(\.slot), [.cell(row: 0, col: 1), .cell(row: 0, col: 0)])
    }

    // MARK: - Grid Rules

    func testWindowsAlreadyInCellsAreNotMoved() {
        XCTAssertEqual(
            plan([
                Candidate(id: 1, frame: left.insetBy(dx: 1, dy: 1), reason: .moved),
                Candidate(id: 2, frame: right, reason: .unchanged),
                Candidate(id: 3, frame: right, reason: .arrived),
            ]),
            [
                Placement(windowID: 1, slot: .cell(row: 0, col: 0), frame: nil),
                Placement(windowID: 2, slot: .cell(row: 0, col: 1), frame: nil),
                Placement(windowID: 3, slot: .cell(row: 0, col: 1), frame: nil),
            ]
        )
    }

    /// An unchanged window a few points off its cell stays in it rather than being
    /// shuffled to whichever cell is free first.
    func testUnchangedWindowSlightlyOffItsCellStaysInIt() {
        let offRight = CGRect(x: 500, y: 0, width: 492, height: 790)
        XCTAssertEqual(
            plan([
                Candidate(id: 1, frame: offRight, reason: .unchanged),
                Candidate(id: 2, frame: somewhere, reason: .arrived),
            ]),
            [
                Placement(windowID: 1, slot: .cell(row: 0, col: 1), frame: right),
                Placement(windowID: 2, slot: .cell(row: 0, col: 0), frame: left),
            ]
        )
    }

    /// Dropping a window on an occupied cell overlaps it; there's no swapping.
    func testMovedWindowGoesWhereDroppedEvenIfTaken() {
        let droppedOnLeft = CGRect(x: 40, y: 60, width: 420, height: 500)
        XCTAssertEqual(
            plan([
                Candidate(id: 1, frame: left, reason: .unchanged),
                Candidate(id: 2, frame: droppedOnLeft, reason: .moved),
            ]),
            [
                Placement(windowID: 1, slot: .cell(row: 0, col: 0), frame: nil),
                Placement(windowID: 2, slot: .cell(row: 0, col: 0), frame: left),
            ]
        )
    }

    func testArrivalsPileOntoTheFirstCellOnceEveryCellIsTaken() {
        let placements = plan([
            Candidate(id: 1, frame: somewhere, reason: .arrived),
            Candidate(id: 2, frame: somewhere, reason: .arrived),
            Candidate(id: 3, frame: somewhere, reason: .arrived),
        ])
        XCTAssertEqual(placements.map(\.slot), [.cell(row: 0, col: 0), .cell(row: 0, col: 1), .cell(row: 0, col: 0)])
    }

    /// On a 1×1 grid the one cell is the whole area, so every window fills the display
    /// either way.
    func testOneByOneGridFillsTheDisplayWithAnyWindowCount() {
        let single = DisplayGridConfig(match: nil, columns: [1], rows: [1], padding: nil)
        XCTAssertEqual(
            plan(
                [
                    Candidate(id: 1, frame: area, reason: .unchanged),
                    Candidate(id: 2, frame: somewhere, reason: .arrived),
                ],
                grid: single
            ),
            [
                Placement(windowID: 1, slot: .cell(row: 0, col: 0), frame: nil),
                Placement(windowID: 2, slot: .cell(row: 0, col: 0), frame: area),
            ]
        )
    }

    // MARK: - Portrait Split With Padding and Gap

    /// Two rows (56.5% / 43.5%) on a padded portrait display with a 4pt gap: a second
    /// window splits it, and closing one maximizes the other again.
    func testRowSplitAndBack() {
        let rows = DisplayGridConfig(match: nil, columns: [1], rows: [565, 435], padding: nil)
        let portrait = CGRect(x: -1496, y: -334, width: 1492, height: 2242)
        let top = TilingGrid.cellRect(row: 0, col: 0, in: portrait, grid: rows, gap: 4)
        let bottom = TilingGrid.cellRect(row: 1, col: 0, in: portrait, grid: rows, gap: 4)
        let newWindow = CGRect(x: -1200, y: 300, width: 800, height: 600)

        let split = AutoTileLayout.plan(
            [
                Candidate(id: 1, frame: portrait, reason: .unchanged),
                Candidate(id: 2, frame: newWindow, reason: .arrived),
            ],
            grid: rows, area: portrait, gap: 4, maximizeSingleWindow: true
        )
        XCTAssertEqual(split, [
            Placement(windowID: 1, slot: .cell(row: 0, col: 0), frame: top),
            Placement(windowID: 2, slot: .cell(row: 1, col: 0), frame: bottom),
        ])

        let alone = AutoTileLayout.plan(
            [Candidate(id: 1, frame: top, reason: .unchanged)],
            grid: rows, area: portrait, gap: 4, maximizeSingleWindow: true
        )
        XCTAssertEqual(alone, [Placement(windowID: 1, slot: .maximized, frame: portrait)])
    }

    // MARK: - Config

    func testMaximizeSingleWindowDefaultsToOn() throws {
        XCTAssertTrue(AutoTileConfig().maximizeSingleWindow)
        let yaml = """
        displays: []
        padding: { top: 0, bottom: 0, left: 0, right: 0, gap: 0 }
        autoTile: { pollingInterval: 2 }
        """
        XCTAssertTrue(try YAMLDecoder().decode(TilingConfig.self, from: yaml).autoTile.maximizeSingleWindow)
    }

    func testMaximizeSingleWindowCanBeTurnedOff() throws {
        let yaml = """
        displays: []
        padding: { top: 0, bottom: 0, left: 0, right: 0, gap: 0 }
        autoTile: { maximizeSingleWindow: false }
        """
        let autoTile = try YAMLDecoder().decode(TilingConfig.self, from: yaml).autoTile
        XCTAssertFalse(autoTile.maximizeSingleWindow)
        XCTAssertEqual(autoTile.pollingInterval, 1.0)
    }

    func testExampleConfigDocumentsTheDefault() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("config.example.yaml")
        let text = try String(contentsOf: example, encoding: .utf8)
        XCTAssertTrue(text.contains("maximizeSingleWindow: true"))
        let config = try ConfigManager.parseYAML(text)
        let tiling = try YAMLDecoder().decode(TilingConfig.self, from: XCTUnwrap(config.moduleConfigs["tiling"]))
        XCTAssertTrue(tiling.autoTile.maximizeSingleWindow)
        XCTAssertTrue(TilingModule.validate(tiling).isValid)
    }
}
