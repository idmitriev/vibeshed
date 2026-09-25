import CoreGraphics

enum GridDirection: String, Sendable {
    case left
    case right
    case up
    case down
}

enum TilingGrid {
    // MARK: - Cell Rect

    /// Returns the exact rect for cell (row, col) within `area`, using the grid's relative
    /// column/row weights. Coordinates follow the CG (top-left origin) convention used
    /// throughout this codebase, so row 0 is the topmost row. `gap` insets each side that
    /// borders another cell by half its value (not sides that border the outer `area`
    /// boundary — that's what padding is for), so two adjacent cells end up separated by
    /// exactly `gap`, matching the convention used elsewhere (e.g. WindowSizing.tileLeft/Right).
    static func cellRect(row: Int, col: Int, in area: CGRect, grid: DisplayGridConfig, gap: Double = 0) -> CGRect {
        guard row >= 0, row < grid.rows.count, col >= 0, col < grid.columns.count else {
            return area
        }
        let colBounds = fractionalBounds(grid.columns)
        let rowBounds = fractionalBounds(grid.rows)

        var x = area.origin.x + colBounds[col] * area.width
        var width = (colBounds[col + 1] - colBounds[col]) * area.width
        var y = area.origin.y + rowBounds[row] * area.height
        var height = (rowBounds[row + 1] - rowBounds[row]) * area.height

        let halfGap = gap / 2.0
        if col > 0 {
            x += halfGap
            width -= halfGap
        }
        if col < grid.columns.count - 1 {
            width -= halfGap
        }
        if row > 0 {
            y += halfGap
            height -= halfGap
        }
        if row < grid.rows.count - 1 {
            height -= halfGap
        }

        return CGRect(x: x, y: y, width: max(width, 0), height: max(height, 0))
    }

    // MARK: - Nearest Cell

    /// Buckets `frame`'s center point into the enclosing (row, col) cell of `area`.
    static func nearestCell(for frame: CGRect, in area: CGRect, grid: DisplayGridConfig) -> (row: Int, col: Int) {
        let colBounds = fractionalBounds(grid.columns)
        let rowBounds = fractionalBounds(grid.rows)

        let fracX = area.width > 0 ? (frame.midX - area.origin.x) / area.width : 0
        let fracY = area.height > 0 ? (frame.midY - area.origin.y) / area.height : 0

        let col = bucketIndex(fracX, in: colBounds)
        let row = bucketIndex(fracY, in: rowBounds)
        return (row: row, col: col)
    }

    // MARK: - Matching Cell

    /// Returns the (row, col) whose exact cell rect already matches `frame` within
    /// `tolerance` on origin and size, or nil if `frame` isn't closely aligned to any
    /// cell. Used to avoid repositioning windows that are already correctly tiled.
    static func matchingCell(
        for frame: CGRect,
        in area: CGRect,
        grid: DisplayGridConfig,
        gap: Double = 0,
        tolerance: Double = 5.0
    ) -> (row: Int, col: Int)? {
        for row in 0 ..< grid.rows.count {
            for col in 0 ..< grid.columns.count {
                let cell = cellRect(row: row, col: col, in: area, grid: grid, gap: gap)
                if abs(frame.origin.x - cell.origin.x) <= tolerance,
                   abs(frame.origin.y - cell.origin.y) <= tolerance,
                   abs(frame.width - cell.width) <= tolerance,
                   abs(frame.height - cell.height) <= tolerance
                {
                    return (row: row, col: col)
                }
            }
        }
        return nil
    }

    // MARK: - Neighbor Cell

    /// Returns the adjacent cell in `direction`, or nil if `cell` is already at that grid edge
    /// (no wraparound).
    static func neighborCell(
        from cell: (row: Int, col: Int),
        direction: GridDirection,
        grid: DisplayGridConfig
    ) -> (row: Int, col: Int)? {
        var row = cell.row
        var col = cell.col
        switch direction {
        case .left:
            col -= 1
        case .right:
            col += 1
        case .up:
            row -= 1
        case .down:
            row += 1
        }
        guard row >= 0, row < grid.rows.count, col >= 0, col < grid.columns.count else {
            return nil
        }
        return (row: row, col: col)
    }

    // MARK: - Weight Resolution

    /// Converts relative weights into cumulative fractional boundaries from 0 to 1
    /// (one more entry than `weights.count`). Falls back to equal division if weights
    /// sum to zero or are empty.
    private static func fractionalBounds(_ weights: [Double]) -> [Double] {
        let total = weights.reduce(0, +)
        guard total > 0, !weights.isEmpty else {
            let count = max(weights.count, 1)
            return (0...count).map { Double($0) / Double(count) }
        }
        var bounds: [Double] = [0]
        var running = 0.0
        for weight in weights {
            running += weight
            bounds.append(running / total)
        }
        return bounds
    }

    private static func bucketIndex(_ fraction: Double, in bounds: [Double]) -> Int {
        let clamped = min(max(fraction, 0), 1)
        for index in 0 ..< (bounds.count - 1) where clamped >= bounds[index] && clamped <= bounds[index + 1] {
            return index
        }
        return max(bounds.count - 2, 0)
    }
}
