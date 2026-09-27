import CoreGraphics
import Foundation

/// Tilings with depth or with rules: isometric terraces and Penrose's aperiodic rhombs.
/// They draw in unit space (`WallpaperCanvas+Units`).
extension WallpaperCanvas {
    // MARK: - Isometric terraces

    /// Isometric blocks stacked to a noise heightmap, painted back to front along the view
    /// diagonal with three shaded faces each; the higher a block, the more of the accent.
    mutating func paintIsometric() {
        enterUnitSpace()
        fill(base)
        let grid = IsometricGrid(tileWidth: 60, levels: 6, width: unitWidth, height: unitHeight)
        let offset = rng.between(0, 100), shades = terraceShades(levels: grid.levels)
        context.setLineJoin(.round)
        context.setLineWidth(hairline(0.8))
        for diagonal in grid.diagonals {
            for column in grid.columns {
                let row = diagonal - column
                guard grid.rows.contains(row) else { continue }
                let elevation = noise.fractal(
                    Double(column) * 0.075 + offset, Double(row) * 0.075 + offset, octaves: 3
                )
                let level = Int(min(max((elevation - 0.28) * 2.3, 0), 1) * (Double(grid.levels) - 0.001))
                guard let block = grid.block(column: column, row: row, level: level) else { continue }
                let shade = shades[level]
                let faces = [(block.leftFace, shade.left), (block.rightFace, shade.right), (block.topFace, shade.top)]
                for (face, color) in faces {
                    context.addLines(between: face)
                    context.closePath()
                    context.setFillColor(color.cgColor)
                    context.fillPath()
                }
                context.addLines(between: block.topFace)
                context.closePath()
                context.setStrokeColor(shade.edge.cgColor)
                context.strokePath()
            }
        }
    }

    /// Face colors per level: tops step from the background toward the accent, the sides
    /// darken, and a faint edge picks out each top.
    private func terraceShades(levels: Int) -> [TerraceShade] {
        let hues = harmony(3)
        return (0 ..< levels).map { level in
            let rise = Double(level) / Double(levels - 1)
            let hue = hues.count > 1 ? hues[1].mix(hues[0], rise) : hues[0]
            let top = palette.background.mix(hue, isDark ? 0.12 + 0.5 * rise : 0.08 + 0.4 * rise)
            return TerraceShade(
                top: top, left: top.mix(.black, isDark ? 0.3 : 0.1), right: top.mix(.black, isDark ? 0.5 : 0.2),
                edge: top.mix(isDark ? .white : .black, 0.07)
            )
        }
    }

    // MARK: - Penrose

    /// Penrose's rhomb tiling by golden-ratio deflation of Robinson triangles: a wheel of ten
    /// triangles around a random point, subdivided until the rhombs are about 50 units
    /// across. Thin rhombs take the accent; thick ones drift between two neighbouring hues.
    mutating func paintPenrose() {
        enterUnitSpace()
        let center = CGPoint(x: unitWidth * rng.between(0.25, 0.75), y: unitHeight * rng.between(0.25, 0.75))
        let radius = hypot(max(center.x, unitWidth - center.x), max(center.y, unitHeight - center.y)) * 1.05
        let wheel = RobinsonTriangle.wheel(center: center, radius: radius, rotation: rng.between(0, 2 * .pi))
        let generations = max(3, Int((log(Double(radius) / 50) / log(RobinsonTriangle.goldenRatio)).rounded()))
        let hues = harmony(3), offset = rng.between(0, 100)
        // Thick rhombs come in a few shades, so each shade is a single fill.
        let shades = 24
        let thickColors = (0 ... shades).map { step in
            let hue = hues.count > 2 ? hues[1].mix(hues[2], Double(step) / Double(shades)) : hues.cycling(1)
            return muted(hue, isDark ? 0.66 : 0.6)
        }
        let thin = CGMutablePath(), thick = (0 ... shades).map { _ in CGMutablePath() }, edges = CGMutablePath()
        for triangle in RobinsonTriangle.deflate(wheel, times: generations) {
            let corners = [triangle.apex, triangle.left, triangle.right]
            if triangle.thin {
                thin.addLines(between: corners)
                thin.closeSubpath()
            } else {
                // The halves of a rhomb share their left–right edge, so its midpoint gives both one shade.
                let middle = triangle.left.interpolated(to: triangle.right, 0.5)
                let drift = noise.fractal(
                    Double(middle.x) / 1000 * 1.3 + offset, Double(middle.y) / 1000 * 1.3 + offset, octaves: 3
                )
                let path = thick[Int((smoothstep(0.35, 0.65, drift) * Double(shades)).rounded())]
                path.addLines(between: corners)
                path.closeSubpath()
            }
            // Rhomb outlines: every half's two outer edges.
            edges.addLines(between: [triangle.right, triangle.apex, triangle.left])
        }
        context.addPath(thin)
        context.setFillColor(muted(hues[0], isDark ? 0.42 : 0.38).cgColor)
        context.fillPath()
        for (path, color) in zip(thick, thickColors) where !path.isEmpty {
            context.addPath(path)
            context.setFillColor(color.cgColor)
            context.fillPath()
        }
        context.addPath(edges)
        context.setStrokeColor(base.cgColor)
        context.setLineJoin(.round)
        context.setLineWidth(3)
        context.strokePath()
    }
}

// MARK: - Isometric grid

/// The terraces' layout: tile (column, row) at level 0 is centered on
/// x = originX + (column − row)·w/2, y = originY + (column + row)·h/2 with h = w/2, and each
/// level lifts it by 0.9·h. The ranges cover every tile that can reach the screen,
/// including tiles lifted into view from below it.
private struct IsometricGrid {
    let tileWidth: CGFloat
    let levels: Int
    let width: CGFloat
    let height: CGFloat
    let columns: ClosedRange<Int>
    let rows: ClosedRange<Int>

    var tileHeight: CGFloat { tileWidth / 2 }
    var lift: CGFloat { tileHeight * 0.9 }
    var originX: CGFloat { width / 2 }
    var originY: CGFloat { -CGFloat(levels) * lift - tileHeight }
    var diagonals: ClosedRange<Int> { columns.lowerBound + rows.lowerBound ... columns.upperBound + rows.upperBound }

    init(tileWidth: CGFloat, levels: Int, width: CGFloat, height: CGFloat) {
        self.tileWidth = tileWidth
        self.levels = levels
        self.width = width
        self.height = height
        let tileHeight = tileWidth / 2, lift = tileHeight * 0.9
        let originX = width / 2, originY = -CGFloat(levels) * lift - tileHeight
        let bottom = height + CGFloat(levels) * lift + tileHeight
        let screen = [
            CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0), CGPoint(x: 0, y: bottom), CGPoint(x: width, y: bottom),
        ]
        let corners = screen.map { corner in
            let across = (corner.x - originX) / (tileWidth / 2), down = (corner.y - originY) / (tileHeight / 2)
            return (column: (across + down) / 2, row: (down - across) / 2)
        }
        let columnSpan = corners.map(\.column), rowSpan = corners.map(\.row)
        columns = Int((columnSpan.min() ?? 0).rounded(.down)) - 1 ... Int((columnSpan.max() ?? 0).rounded(.up)) + 1
        rows = Int((rowSpan.min() ?? 0).rounded(.down)) - 1 ... Int((rowSpan.max() ?? 0).rounded(.up)) + 1
    }

    /// The block at (column, row) raised `level` steps, or nil if it can't be seen.
    func block(column: Int, row: Int, level: Int) -> IsometricBlock? {
        let centerX = originX + CGFloat(column - row) * tileWidth / 2
        let ground = originY + CGFloat(column + row) * tileHeight / 2, top = ground - CGFloat(level) * lift
        guard centerX >= -tileWidth, centerX <= width + tileWidth, top - tileHeight <= height else { return nil }
        return IsometricBlock(
            centerX: centerX, top: top, floor: ground + 4 * lift, halfWidth: tileWidth / 2, halfHeight: tileHeight / 2
        )
    }
}

private struct TerraceShade {
    let top: ThemeColor
    let left: ThemeColor
    let right: ThemeColor
    let edge: ThemeColor
}

/// One terrace column: a diamond top centered at (`centerX`, `top`) and two side faces
/// running down to `floor`, where nearer blocks hide them.
private struct IsometricBlock {
    let centerX: CGFloat
    let top: CGFloat
    let floor: CGFloat
    let halfWidth: CGFloat
    let halfHeight: CGFloat

    var topFace: [CGPoint] {
        [
            CGPoint(x: centerX, y: top - halfHeight), CGPoint(x: centerX + halfWidth, y: top),
            CGPoint(x: centerX, y: top + halfHeight), CGPoint(x: centerX - halfWidth, y: top),
        ]
    }

    var leftFace: [CGPoint] { side(centerX - halfWidth) }
    var rightFace: [CGPoint] { side(centerX + halfWidth) }

    private func side(_ edgeX: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: edgeX, y: top), CGPoint(x: centerX, y: top + halfHeight),
            CGPoint(x: centerX, y: floor + halfHeight), CGPoint(x: edgeX, y: floor),
        ]
    }
}

// MARK: - Robinson triangles

/// Half of a Penrose rhomb. Thin halves (36° at the apex) pair up into thin rhombs and
/// thick halves into thick rhombs, always along their `left`–`right` edge.
struct RobinsonTriangle {
    static let goldenRatio = (1 + sqrt(5.0)) / 2

    let thin: Bool
    let apex: CGPoint
    let left: CGPoint
    let right: CGPoint

    /// Ten thin halves fanned around `center`, alternately mirrored as the deflation needs.
    static func wheel(center: CGPoint, radius: CGFloat, rotation: Double) -> [RobinsonTriangle] {
        let corner = { (step: Int) in
            let angle = rotation + Double(step) * .pi / 10
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        return (0 ..< 10).map { index in
            let (first, second) = (corner(2 * index - 1), corner(2 * index + 1))
            return index.isMultiple(of: 2)
                ? RobinsonTriangle(thin: true, apex: center, left: second, right: first)
                : RobinsonTriangle(thin: true, apex: center, left: first, right: second)
        }
    }

    /// The smaller halves this one splits into, each 1/φ its size.
    func deflated() -> [RobinsonTriangle] {
        let ratio = 1 / Self.goldenRatio
        if thin {
            let split = apex.interpolated(to: left, ratio)
            return [
                RobinsonTriangle(thin: true, apex: right, left: split, right: left),
                RobinsonTriangle(thin: false, apex: split, left: right, right: apex),
            ]
        }
        let onSide = left.interpolated(to: apex, ratio), onBase = left.interpolated(to: right, ratio)
        return [
            RobinsonTriangle(thin: false, apex: onBase, left: right, right: apex),
            RobinsonTriangle(thin: false, apex: onSide, left: onBase, right: left),
            RobinsonTriangle(thin: true, apex: onBase, left: onSide, right: apex),
        ]
    }

    static func deflate(_ triangles: [RobinsonTriangle], times: Int) -> [RobinsonTriangle] {
        (0 ..< times).reduce(triangles) { current, _ in current.flatMap { $0.deflated() } }
    }
}
