import CoreGraphics
import Foundation

/// Classic-OS and classic-computing styles, painted from whatever palette is active.
/// Themes can pin the desktop color with a `desktop` key (the retro themes do). Haiku's
/// Leaves, NeXT's Polyhedra and Windows NT's Pipes live in `WallpaperCanvas+ScreenSavers`.
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

// MARK: - 10 PRINT and Dither

extension WallpaperCanvas {
    /// `10 PRINT CHR$(205.5+RND(1)); : GOTO 10`, the Commodore 64 one-liner: a maze of
    /// random diagonals (in unit space). The rooms it seals off, regions that never reach
    /// the edge, are found with union-find and most of them are tinted.
    mutating func paintMaze() {
        enterUnitSpace()
        fill(base)
        let cell: CGFloat = 30
        let columns = Int((unitWidth / cell).rounded(.up)), rows = Int((unitHeight / cell).rounded(.up))
        let maze = DiagonalMaze(
            columns: columns, rows: rows, rising: (0 ..< columns * rows).map { _ in rng.int(below: 2) == 1 }
        )
        let tints = harmony(4).map { muted($0, isDark ? 0.5 : 0.45) }
        let shapes = tints.map { _ in CGMutablePath() }
        var tintOfRoom: [Int: Int] = [:] // −1 leaves a room untinted
        for (half, room) in maze.rooms().enumerated() {
            guard let room else { continue }
            let tint = tintOfRoom[room] ?? (rng.unit() < 0.3 ? -1 : rng.int(below: tints.count))
            tintOfRoom[room] = tint
            guard tint >= 0 else { continue }
            shapes[tint].addLines(between: maze.triangle(half, cell: cell))
            shapes[tint].closeSubpath()
        }
        for (shape, tint) in zip(shapes, tints) {
            context.addPath(shape)
            context.setFillColor(tint.cgColor)
            context.fillPath()
        }
        let walls = CGMutablePath()
        for index in 0 ..< columns * rows {
            walls.addLines(between: maze.wall(index, cell: cell))
        }
        context.addPath(walls)
        context.setLineCap(.round)
        context.setLineWidth(3.4)
        context.setStrokeColor(muted(palette.foreground, isDark ? 0.4 : 0.3).cgColor)
        context.strokePath()
    }

    /// The 8×8 Bayer matrix as thresholds in `0 ..< 1`.
    static let bayer: [Double] = [
        0, 48, 12, 60, 3, 51, 15, 63, 32, 16, 44, 28, 35, 19, 47, 31, 8, 56, 4, 52, 11, 59, 7, 55,
        40, 24, 36, 20, 43, 27, 39, 23, 2, 50, 14, 62, 1, 49, 13, 61, 34, 18, 46, 30, 33, 17, 45, 29,
        10, 58, 6, 54, 9, 57, 5, 53, 42, 26, 38, 22, 41, 25, 37, 21,
    ].map { $0 / 64 }

    /// A lit, banded planet in four tones, ordered-dithered with the Bayer matrix into chunky
    /// pixels: the look of 1-bit Macs and 2-bit NeXT screens. Computed as a small bitmap
    /// (a whole number of device pixels per dot) and scaled up without smoothing.
    mutating func paintDither() {
        let dot = max(1, (4.4 * unit).rounded())
        let columns = Int((width / dot).rounded(.up)), rows = Int((height / dot).rounded(.up))
        let planet = DitherPlanet(
            radius: Double(rows) * rng.between(0.36, 0.46), centerX: Double(columns) * rng.between(0.56, 0.74),
            centerY: Double(rows) * rng.between(0.46, 0.6), tilt: rng.between(-0.4, 0.4),
            bands: rng.between(7, 12), offset: rng.between(0, 50)
        )
        let tones = ditherTones().map { [UInt8($0.red8), UInt8($0.green8), UInt8($0.blue8)] }
        var pixels = [UInt8](repeating: 255, count: columns * rows * 4)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                var light = planet.light(column: column, row: row, rows: rows, noise: noise)
                if light.sky, isDark, rng.unit() < 0.0035 { light.value = 0.6 + 0.4 * rng.unit() }
                let level = min(max(Int(light.value * 3 + Self.bayer[(row % 8) * 8 + column % 8]), 0), 3)
                let offset = (row * columns + column) * 4
                pixels.replaceSubrange(offset ..< offset + 3, with: tones[level])
            }
        }
        guard let image = bitmapImage(columns: columns, rows: rows, pixels: pixels) else { return fill(base) }
        let size = CGSize(width: CGFloat(columns) * dot, height: CGFloat(rows) * dot)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: CGPoint(x: 0, y: height - size.height), size: size))
    }

    /// Four tones, darkest first: shades of the accent over the ground.
    private func ditherTones() -> [ThemeColor] {
        let accent = palette.accent
        if isDark {
            return [base, base.mix(accent, 0.28), base.mix(accent, 0.62), accent.mix(palette.brightForeground, 0.55)]
        }
        let paper = palette.background
        return [palette.foreground.mix(accent, 0.25), paper.mix(accent, 0.55), paper.mix(accent, 0.2), paper]
    }
}

/// The 10 PRINT maze: every cell holds one diagonal, splitting it into two triangular
/// halves. Half `2·cell` holds the cell's top edge, `2·cell + 1` its bottom edge.
struct DiagonalMaze {
    let columns: Int
    let rows: Int
    /// Per cell, row-major: `true` for ╱ (bottom-left to top-right), `false` for ╲.
    let rising: [Bool]

    private enum Side {
        case top, right, bottom, left
    }

    /// The half of `cell` that touches `side`.
    private func half(_ cell: Int, _ side: Side) -> Int {
        let upper = switch side {
        case .top: true
        case .bottom: false
        case .right: !rising[cell] // ╲ keeps the right edge with the top, ╱ the left
        case .left: rising[cell]
        }
        return 2 * cell + (upper ? 0 : 1)
    }

    /// For every half, the id of the sealed room it's in, or nil when its region reaches the
    /// edge of the grid.
    func rooms() -> [Int?] {
        var parent = Array(0 ..< columns * rows * 2)
        func root(_ node: Int) -> Int {
            var node = node
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }
        func join(_ first: Int, _ second: Int) {
            let (firstRoot, secondRoot) = (root(first), root(second))
            if firstRoot != secondRoot { parent[firstRoot] = secondRoot }
        }
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                let cell = row * columns + column
                if column + 1 < columns { join(half(cell, .right), half(cell + 1, .left)) }
                if row + 1 < rows { join(half(cell, .bottom), half(cell + columns, .top)) }
            }
        }
        var open = Set<Int>()
        for column in 0 ..< columns {
            open.insert(root(half(column, .top)))
            open.insert(root(half((rows - 1) * columns + column, .bottom)))
        }
        for row in 0 ..< rows {
            open.insert(root(half(row * columns, .left)))
            open.insert(root(half(row * columns + columns - 1, .right)))
        }
        return (0 ..< columns * rows * 2).map { node in
            let room = root(node)
            return open.contains(room) ? nil : room
        }
    }

    /// The corners of `half` in a grid of `cell`-sized squares, y down.
    func triangle(_ half: Int, cell: CGFloat) -> [CGPoint] {
        let index = half / 2
        let left = CGFloat(index % columns) * cell, top = CGFloat(index / columns) * cell
        let right = left + cell, bottom = top + cell
        return switch (rising[index], half.isMultiple(of: 2)) {
        case (false, true): [CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: right, y: bottom)]
        case (false, false): [CGPoint(x: left, y: top), CGPoint(x: left, y: bottom), CGPoint(x: right, y: bottom)]
        case (true, true): [CGPoint(x: left, y: top), CGPoint(x: right, y: top), CGPoint(x: left, y: bottom)]
        case (true, false): [CGPoint(x: right, y: top), CGPoint(x: right, y: bottom), CGPoint(x: left, y: bottom)]
        }
    }

    /// The diagonal across cell `index`.
    func wall(_ index: Int, cell: CGFloat) -> [CGPoint] {
        let left = CGFloat(index % columns) * cell, top = CGFloat(index / columns) * cell
        return rising[index]
            ? [CGPoint(x: left, y: top + cell), CGPoint(x: left + cell, y: top)]
            : [CGPoint(x: left, y: top), CGPoint(x: left + cell, y: top + cell)]
    }
}

/// The dither style's scene, in grid pixels with y down: a planet lit from the upper left
/// with tilted bands, a thin atmosphere on its lit side, and a sky brightening downward.
private struct DitherPlanet {
    let radius: Double
    let centerX: Double
    let centerY: Double
    let tilt: Double
    let bands: Double
    let offset: Double

    private static let sun: (x: Double, y: Double, z: Double) = {
        let length = (0.55 * 0.55 + 0.5 * 0.5 + 0.67 * 0.67).squareRoot()
        return (-0.55 / length, -0.5 / length, 0.67 / length)
    }()

    /// Brightness in `0...1` at a grid pixel, and whether it's open sky.
    func light(column: Int, row: Int, rows: Int, noise: ValueNoise) -> (value: Double, sky: Bool) {
        let dx = (Double(column) - centerX) / radius, dy = (Double(row) - centerY) / radius
        let squared = dx * dx + dy * dy, sun = Self.sun
        if squared < 1 {
            let diffuse = max(0, dx * sun.x + dy * sun.y + (1 - squared).squareRoot() * sun.z)
            let across = dy * cos(tilt) + dx * sin(tilt)
            let band = 0.5 + 0.5 * sin(across * bands * 2 + (noise.value(across * 6 + offset, offset) - 0.5) * 3)
            return (0.04 + 0.96 * pow(diffuse, 0.85) * (0.72 + 0.28 * band), false)
        }
        let distance = squared.squareRoot(), facing = (dx * sun.x + dy * sun.y) / distance
        let atmosphere = exp(-(distance - 1) * 14) * min(max(0.35 + 0.65 * facing, 0), 1)
        return (0.03 + 0.16 * pow(Double(row) / Double(rows), 2) + 0.55 * atmosphere, true)
    }
}
