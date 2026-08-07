import AppKit
import CoreGraphics

/// Grid-split scanning shared by the tiling module's swap/focus navigation actions
/// (TilingModule+SplitActions.swift).
enum TilingSplits {
    /// Snapshot of the focused window's grid and which windows sit in which split.
    /// Cells are addressed by row-major index; `windowsByCell` lists are front-to-back
    /// z-order, so `.first` is the visible (topmost) window of a split.
    struct Scan {
        let focused: WindowInfo
        let grid: DisplayGridConfig
        let area: CGRect
        let gap: Double
        let displayKey: String
        let currentCellIndex: Int
        let cellCount: Int
        let windowsByCell: [Int: [WindowInfo]]
    }

    /// Nil when there's no focused window or no grid configured for its display.
    /// Only windows on the focused window's screen participate — splits are per-display.
    @MainActor
    static func scan(manager: TilingManager, config: TilingConfig) -> Scan? {
        guard let focused = manager.getFocusedWindow(),
              let resolved = manager.resolveGrid(for: focused.frame, config: config)
        else { return nil }
        let grid = resolved.grid
        let cols = grid.columns.count
        let currentCell = TilingGrid.nearestCell(for: focused.frame, in: resolved.area, grid: grid)
        let focusedScreen = WindowListHelper.screen(forFrame: focused.frame)
        var windowsByCell: [Int: [WindowInfo]] = [:]
        for window in manager.listWindows(includeMinimized: false)
            where window.id != focused.id
            && WindowListHelper.screen(forFrame: window.frame) == focusedScreen
        {
            let cell = TilingGrid.nearestCell(for: window.frame, in: resolved.area, grid: grid)
            windowsByCell[cell.row * cols + cell.col, default: []].append(window)
        }
        return Scan(
            focused: focused,
            grid: grid,
            area: resolved.area,
            gap: resolved.gap,
            displayKey: resolved.displayKey,
            currentCellIndex: currentCell.row * cols + currentCell.col,
            cellCount: cols * grid.rows.count,
            windowsByCell: windowsByCell
        )
    }

    /// First occupied split walking from the current cell in cyclic row-major order
    /// (`step` +1 forward / -1 backward), with its visible (topmost) window. Nil when
    /// every other split is empty.
    static func occupiedSplit(in scan: Scan, step: Int) -> (cellIndex: Int, window: WindowInfo)? {
        guard scan.cellCount > 1 else { return nil }
        for offset in 1 ..< scan.cellCount {
            let index = ((scan.currentCellIndex + step * offset) % scan.cellCount + scan.cellCount) % scan.cellCount
            if let window = scan.windowsByCell[index]?.first {
                return (cellIndex: index, window: window)
            }
        }
        return nil
    }

    static func cell(at cellIndex: Int, in scan: Scan) -> (row: Int, col: Int) {
        let cols = scan.grid.columns.count
        return (row: cellIndex / cols, col: cellIndex % cols)
    }

    static func cellRect(at cellIndex: Int, in scan: Scan) -> CGRect {
        let cell = cell(at: cellIndex, in: scan)
        return TilingGrid.cellRect(
            row: cell.row, col: cell.col,
            in: scan.area, grid: scan.grid, gap: scan.gap
        )
    }

    /// Fallback focus cycling when split navigation doesn't apply (no grid, or no other
    /// occupied split): treat the on-screen z-order as the recently-focused queue —
    /// CGWindowList returns windows front-to-back, and focusing raises — and step through
    /// it. Forward goes to the most recently focused other window; backward to the least.
    static func focusRecentWindow(manager: TilingManager, forward: Bool) async throws -> ActionResult {
        let (windows, focusedID) = await MainActor.run {
            (manager.listWindows(includeMinimized: false), manager.getFocusedWindow()?.id)
        }
        guard windows.count > 1 else {
            return .showResult(title: "No Window", body: "No other window to focus")
        }
        let currentIndex = focusedID.flatMap { id in windows.firstIndex { $0.id == id } } ?? 0
        let target = forward
            ? windows[(currentIndex + 1) % windows.count]
            : windows[(currentIndex - 1 + windows.count) % windows.count]
        guard target.id != focusedID else { return .dismiss }
        try manager.focusWindow(target)
        return .dismiss
    }
}
