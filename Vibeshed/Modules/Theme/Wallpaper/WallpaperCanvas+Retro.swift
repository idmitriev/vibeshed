import CoreGraphics
import Foundation

/// Classic-OS styles, painted from whatever palette is active. Themes can pin the
/// desktop color with a `desktop` key (the retro themes do). Haiku's Leaves and NeXT's
/// Polyhedra live in `WallpaperCanvas+ScreenSavers`.
extension WallpaperCanvas {
    // MARK: - OS/2 Warp

    /// Star streaks rushing out of a vanishing point — the "Warp" in OS/2 Warp.
    mutating func paintWarp() {
        let space = isDark ? palette.darkerBackground : palette.foreground.mix(.black, 0.6)
        fill(space)
        let center = point(rng.between(0.42, 0.58), rng.between(0.42, 0.58))
        let reach = hypot(width, height) * 0.62
        glow(palette.accent.mix(.white, 0.2), at: center, radius: reach * 0.55, alpha: 0.4)
        glow(palette.cyan, at: center, radius: reach * 0.9, alpha: 0.12)
        let tones = harmony(3) + [.white]
        context.setLineCap(.round)
        for _ in 0 ..< 420 {
            let angle = rng.between(0, .pi * 2)
            let start = pow(rng.unit(), 1.5) * reach * 0.95 + unit * 10
            let length = start * rng.between(0.1, 0.45) + unit * 6
            let depth = min(start / reach, 1)
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let color = tones[Int(rng.between(0, Double(tones.count)))].mix(.white, rng.between(0.2, 0.6))
            context.setStrokeColor(color.cgColor.copy(alpha: 0.15 + 0.75 * depth) ?? color.cgColor)
            context.setLineWidth(unit * (0.6 + 3.4 * depth))
            context.move(to: CGPoint(x: center.x + direction.x * start, y: center.y + direction.y * start))
            context.addLine(to: CGPoint(x: center.x + direction.x * (start + length),
                                        y: center.y + direction.y * (start + length)))
            context.strokePath()
        }
    }

    // MARK: - Text mode

    /// An 80s/90s text-mode screen: shaded desktop, menu bar, status line and boxed dialogs
    /// on a character grid, colored from the palette's 16 terminal colors.
    mutating func paintTextMode() {
        let ansi = palette.ansi
        let cellWidth = width / 96
        let cellHeight = cellWidth * 2
        let rows = Int(height / cellHeight)
        let desktop = palette["desktop"] ?? (isDark ? palette.background : ansi[4])
        fill(desktop)
        // ░ shading: two dots per cell.
        let dot = desktop.mix(palette.foreground, 0.14)
        context.setFillColor(dot.cgColor)
        for row in 0 ..< rows {
            for column in 0 ..< 96 {
                let x = CGFloat(column) * cellWidth, y = CGFloat(row) * cellHeight
                let side = cellWidth * 0.2
                context.fill(CGRect(x: x + cellWidth * 0.2, y: y + cellHeight * 0.2, width: side, height: side))
                context.fill(CGRect(x: x + cellWidth * 0.6, y: y + cellHeight * 0.6, width: side, height: side))
            }
        }
        let grid = TextGrid(cellWidth: cellWidth, cellHeight: cellHeight, rows: rows)
        // Menu bar (top row) with one highlighted item, status line (bottom row).
        fillRect(grid.rect(column: 0, row: 0, columns: 96, rows: 1), ansi[7])
        for item in 0 ..< 5 {
            let cell = grid.rect(column: 2 + item * 9, row: 0, columns: 7, rows: 1)
            if item == 1 { fillRect(cell, ansi[0]) }
            greek(grid.textLine(in: cell), color: item == 1 ? ansi[15] : ansi[0])
        }
        fillRect(grid.rect(column: 0, row: rows - 1, columns: 96, rows: 1), ansi[6])
        for key in 0 ..< 6 {
            let cell = grid.rect(column: 1 + key * 12, row: rows - 1, columns: 10, rows: 1)
            let label = grid.rect(column: 1 + key * 12, row: rows - 1, columns: 2, rows: 1)
            greek(grid.textLine(in: label), color: ansi[1])
            greek(grid.textLine(in: cell.insetBy(dx: cellWidth * 1.5, dy: 0)), color: ansi[0])
        }
        let colors = [(ansi[7], ansi[15]), (ansi[6], ansi[15]), (ansi[7], ansi[0])]
        for (index, pair) in colors.enumerated() {
            let columns = Int(rng.between(28, 44)), lines = Int(rng.between(7, 12))
            let dialog = TextDialog(
                column: Int(rng.between(4, Double(96 - columns - 4))),
                row: Int(rng.between(3, Double(max(4, rows - lines - 4)))),
                columns: columns, rows: lines, fill: pair.0, border: pair.1, titled: index == colors.count - 1
            )
            drawTextDialog(dialog, grid: grid)
        }
    }

    private mutating func drawTextDialog(_ dialog: TextDialog, grid: TextGrid) {
        let ansi = palette.ansi
        let (column, row, size) = (dialog.column, dialog.row, (columns: dialog.columns, rows: dialog.rows))
        let colors = (fill: dialog.fill, border: dialog.border)
        let titled = dialog.titled
        let box = grid.rect(column: column, row: row, columns: size.columns, rows: size.rows)
        fillRect(box.offsetBy(dx: grid.cellWidth * 2, dy: -grid.cellHeight), ansi[0].mix(.black, 0.3))
        fillRect(box, colors.fill)
        // Double-line frame through the middle of the outer cells.
        let outer = box.insetBy(dx: grid.cellWidth * 0.5, dy: grid.cellHeight * 0.5)
        context.setStrokeColor(colors.border.cgColor)
        context.setLineWidth(max(1, grid.cellWidth * 0.12))
        context.stroke(outer.insetBy(dx: -grid.cellWidth * 0.14, dy: -grid.cellWidth * 0.14))
        context.stroke(outer.insetBy(dx: grid.cellWidth * 0.14, dy: grid.cellWidth * 0.14))
        if titled {
            let title = grid.rect(column: column + size.columns / 2 - 6, row: row, columns: 12, rows: 1)
            fillRect(title, palette.accent)
            greek(grid.textLine(in: title.insetBy(dx: grid.cellWidth, dy: 0)), color: palette.accent.contrastingText)
        }
        for line in 2 ..< size.rows - 1 {
            let length = Int(rng.between(6, Double(size.columns - 6)))
            greek(grid.textLine(in: grid.rect(column: column + 3, row: row + line, columns: length, rows: 1)),
                  color: colors.fill.contrastingText)
        }
    }

    // MARK: - Shared primitives

    func fillRect(_ rect: CGRect, _ color: ThemeColor) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    /// A rounded bar standing in for a line of text.
    func greek(_ rect: CGRect, color: ThemeColor) {
        context.setFillColor(color.cgColor)
        let radius = rect.height / 2
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
    }
}

/// Character-cell geometry for the text-mode style; row 0 is the top line.
private struct TextGrid {
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let rows: Int

    func rect(column: Int, row: Int, columns: Int, rows count: Int) -> CGRect {
        CGRect(
            x: CGFloat(column) * cellWidth,
            y: CGFloat(rows - row - count) * cellHeight,
            width: CGFloat(columns) * cellWidth,
            height: CGFloat(count) * cellHeight
        )
    }

    /// The glyph band of a text cell run (x-height, vertically centered).
    func textLine(in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + cellWidth * 0.1, y: rect.midY - cellHeight * 0.14,
               width: rect.width - cellWidth * 0.2, height: cellHeight * 0.28)
    }
}

/// A boxed dialog on the text-mode grid.
private struct TextDialog {
    let column: Int
    let row: Int
    let columns: Int
    let rows: Int
    let fill: ThemeColor
    let border: ThemeColor
    let titled: Bool
}
