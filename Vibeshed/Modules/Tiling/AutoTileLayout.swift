import CoreGraphics

/// Where auto-tile puts one display's windows. Pure geometry — no AX, no AppKit — so the
/// rules are unit-testable: TilingModule gathers each display's eligible windows, plans
/// them here, and applies the resulting frames.
///
/// With `maximizeSingleWindow`, a display's only window fills its whole usable area; from
/// two windows up (or always, without it) each window takes a grid cell.
enum AutoTileLayout {
    /// Why a window is being laid out, which decides where it goes when it isn't already
    /// in place.
    enum Reason {
        /// It appeared on screen, or everything is being tiled at once (enabling
        /// auto-tile, attachAll): the first free cell.
        case arrived
        /// It moved or resized since the last poll: the cell under its center, taken or
        /// not, since where the user dropped it says where they want it.
        case moved
        /// Its frame is unchanged; it's laid out because another window on its display
        /// changed. It stays in the cell it sits in — or, if it still fills the display
        /// because it was alone until now, moves to the nearest free cell.
        case unchanged
    }

    struct Candidate {
        let id: Int
        let frame: CGRect
        let reason: Reason
    }

    enum Slot: Equatable {
        /// The display's whole usable area.
        case maximized
        case cell(row: Int, col: Int)
    }

    struct Placement: Equatable {
        let windowID: Int
        let slot: Slot
        /// The frame to set, or nil when the window already sits in its slot.
        let frame: CGRect?
    }

    /// One placement per candidate, in input order. Candidates should come front to back,
    /// as CGWindowList lists them: arrivals fill free cells in that order.
    static func plan(
        _ candidates: [Candidate],
        grid: DisplayGridConfig,
        area: CGRect,
        gap: Double,
        maximizeSingleWindow: Bool
    ) -> [Placement] {
        var cells = Cells(grid: grid, area: area, gap: gap)
        if maximizeSingleWindow, candidates.count == 1, let only = candidates.first {
            let frame = cells.fillsArea(only.frame) ? nil : area
            return [Placement(windowID: only.id, slot: .maximized, frame: frame)]
        }

        var placements: [Int: Placement] = [:]
        func place(_ candidate: Candidate, in cell: (row: Int, col: Int), alreadyThere: Bool = false) {
            cells.claim(cell)
            placements[candidate.id] = Placement(
                windowID: candidate.id,
                slot: .cell(row: cell.row, col: cell.col),
                frame: alreadyThere ? nil : cells.rect(cell)
            )
        }
        func unplaced(_ reasons: Reason...) -> [Candidate] {
            candidates.filter { placements[$0.id] == nil && reasons.contains($0.reason) }
        }

        // Windows already filling a cell keep it, whatever brought them here.
        for candidate in candidates {
            if let cell = cells.matching(candidate.frame) {
                place(candidate, in: cell, alreadyThere: true)
            }
        }
        // Moved windows go where they were dropped; unchanged ones stay in the cell they sit
        // in, even when their app holds them a few points off it.
        for candidate in unplaced(.moved, .unchanged)
            where candidate.reason == .moved || !cells.isNearerArea(candidate.frame)
        {
            place(candidate, in: cells.nearest(candidate.frame))
        }
        // A window still filling the display, alone there until now, shrinks into the free
        // cell under its center, or failing that the first free one.
        for candidate in unplaced(.unchanged) {
            place(candidate, in: cells.nearestFree(to: candidate.frame))
        }
        // Arrivals take the first free cell, piling onto (0, 0) once every cell is taken.
        for candidate in unplaced(.arrived) {
            place(candidate, in: cells.firstFree ?? (row: 0, col: 0))
        }
        return candidates.compactMap { placements[$0.id] }
    }
}

/// One display's grid geometry, plus the cells a plan has handed out so far.
private struct Cells {
    let grid: DisplayGridConfig
    let area: CGRect
    let gap: Double
    private var taken: Set<Int> = []

    init(grid: DisplayGridConfig, area: CGRect, gap: Double) {
        self.grid = grid
        self.area = area
        self.gap = gap
    }

    func rect(_ cell: (row: Int, col: Int)) -> CGRect {
        TilingGrid.cellRect(row: cell.row, col: cell.col, in: area, grid: grid, gap: gap)
    }

    /// The cell `frame` already fills (5pt tolerance), if any.
    func matching(_ frame: CGRect) -> (row: Int, col: Int)? {
        TilingGrid.matchingCell(for: frame, in: area, grid: grid, gap: gap)
    }

    /// The cell under `frame`'s center.
    func nearest(_ frame: CGRect) -> (row: Int, col: Int) {
        TilingGrid.nearestCell(for: frame, in: area, grid: grid)
    }

    /// The first unclaimed cell in row-major order, or nil when every cell is claimed.
    var firstFree: (row: Int, col: Int)? {
        let columns = grid.columns.count
        return (0 ..< grid.rows.count * columns)
            .first { !taken.contains($0) }
            .map { (row: $0 / columns, col: $0 % columns) }
    }

    /// The cell under `frame`'s center if it's unclaimed, else the first unclaimed one,
    /// else the cell under its center anyway.
    func nearestFree(to frame: CGRect) -> (row: Int, col: Int) {
        let cell = nearest(frame)
        return taken.contains(index(of: cell)) ? (firstFree ?? cell) : cell
    }

    mutating func claim(_ cell: (row: Int, col: Int)) {
        taken.insert(index(of: cell))
    }

    /// Whether `frame` fills the whole area — the maximized slot — within the same 5pt
    /// tolerance `matching` uses for cells.
    func fillsArea(_ frame: CGRect, tolerance: Double = 5.0) -> Bool {
        abs(frame.minX - area.minX) <= tolerance && abs(frame.minY - area.minY) <= tolerance
            && abs(frame.width - area.width) <= tolerance && abs(frame.height - area.height) <= tolerance
    }

    /// Whether `frame` is closer to the whole area than to the cell under its center, as
    /// a maximized window is even when its app keeps it a little short of the area. False
    /// on a 1×1 grid, where the cell is the area.
    func isNearerArea(_ frame: CGRect) -> Bool {
        Self.offset(of: frame, from: area) < Self.offset(of: frame, from: rect(nearest(frame)))
    }

    private func index(of cell: (row: Int, col: Int)) -> Int {
        cell.row * grid.columns.count + cell.col
    }

    /// Sum of the distances between `frame`'s edges and `slot`'s.
    private static func offset(of frame: CGRect, from slot: CGRect) -> Double {
        abs(frame.minX - slot.minX) + abs(frame.minY - slot.minY)
            + abs(frame.maxX - slot.maxX) + abs(frame.maxY - slot.maxY)
    }
}
