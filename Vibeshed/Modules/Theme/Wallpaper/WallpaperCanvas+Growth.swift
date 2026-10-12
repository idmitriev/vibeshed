import CoreGraphics
import Foundation

/// Differential growth: a closed ring of nodes that folds as it grows, drawn at every stage
/// so the stages read as relief. Simulated on the render lanes; drawn in unit space.
///
/// Adapted from gart (https://github.com/igr/gart), © 2022 Igor Spasić, BSD 2-Clause License.
extension WallpaperCanvas {
    /// gart's Rugae, after Anders Hoff's differential-line: a ring of nodes that pull toward
    /// their neighbors' midpoint, push away from every other node nearby and split their
    /// edges where they stretch, with noise feeding extra splits in rich patches. Crowded
    /// into itself, the ring folds like brain coral. Every fifth step is drawn as a closed
    /// line, the palette sweeping twice from the oldest to the newest, and the strokes pile
    /// up into shaded relief. Shorter than Rugae (600 steps, 6000 nodes rather than 950 and
    /// 9000), so a debug build still paints it in about a second.
    mutating func paintGrowth() {
        enterUnitSpace()
        let scale = 1000.0 / 1200
        let center = CGPoint(x: unitWidth * rng.between(0.4, 0.6), y: 1000 * rng.between(0.45, 0.55))
        let ring = (0 ..< 50).map { node -> CGPoint in
            let angle = Double(node) / 50 * 2 * .pi, radius = rng.between(46, 50) * scale
            return CGPoint(x: center.x + cos(angle) * radius * 1.6, y: center.y + sin(angle) * radius)
        }
        let noise = self.noise, shift = rng.between(0, 100), feed = 0.0042 / scale
        let food = SampledField(over: CGRect(x: 0, y: 0, width: unitWidth, height: 1000), spacing: 10) { x, y in
            noise.fractal(x * feed + shift, y * feed, octaves: 2)
        }
        let growth = DifferentialGrowth(ring: ring, size: CGSize(width: unitWidth, height: 1000), scale: scale)
        let stages = growth.run(steps: 600, every: 5, food: food, using: &rng)
        fill(base)
        paintStages(stages)
    }

    /// The stages, then the final ring in the foreground. Core Graphics spends about 100 ns
    /// on every pixel of length of strokes like these, and the stages add up to millions, so
    /// they're drawn at half resolution and scaled up: the relief they build is soft anyway.
    /// Only the final ring is drawn at full resolution.
    private func paintStages(_ stages: [[CGPoint]]) {
        let columns = max(Int(width / 2), 1), rows = max(Int(height / 2), 1)
        if let half = CGContext(
            data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) {
            half.setFillColor(base.cgColor)
            half.fill(CGRect(x: 0, y: 0, width: columns, height: rows))
            half.translateBy(x: 0, y: CGFloat(rows))
            half.scaleBy(x: CGFloat(rows) / unitHeight, y: -CGFloat(rows) / unitHeight)
            half.setLineJoin(.round)
            half.setLineCap(.round)
            let sweep = growthSweep(), last = Double(max(stages.count - 1, 1))
            for (index, stage) in stages.enumerated() {
                let age = Double(index) / last
                let tone = sweep.ramp((age * 2).truncatingRemainder(dividingBy: 1))
                half.setStrokeColor(tone.cgColor(alpha: 0.6 + 0.4 * age))
                half.setLineWidth(1 + 0.5 * age)
                half.addLines(between: stage)
                half.closePath()
                half.strokePath()
            }
            if let image = half.makeImage() {
                drawUpright(image, in: CGRect(x: 0, y: 0, width: unitWidth, height: unitHeight))
            }
        }
        context.setLineJoin(.round)
        context.setStrokeColor(palette.foreground.cgColor(alpha: 0.95))
        context.setLineWidth(1.7)
        context.addLines(between: stages.last ?? [])
        context.closePath()
        context.strokePath()
    }

    /// Five stops the stages sweep through, ending where they started.
    private func growthSweep() -> [ThemeColor] {
        let hues = harmony(4, keepingTwin: true)
        func hue(_ index: Int) -> ThemeColor {
            index < hues.count ? hues[index] : hues[0]
        }
        return isDark
            ? [muted(hue(1), 0.45), hue(0), muted(hue(2), 0.1), hue(3), muted(hue(1), 0.45)]
            : [
                hue(1).mix(palette.background, 0.5), hue(0), hue(2).darkened(0.15), hue(3),
                hue(1).mix(palette.background, 0.5),
            ]
    }
}

/// gart's Rugae constants, in units of a 1200-tall canvas, and a lower node cap.
private struct GrowthRules: Sendable {
    let split: Double
    let radius: Double
    let maximumStep: Double
    let margin: Double
    let size: CGSize
    static let attraction = 0.45
    static let repulsion = 1.2
    static let brownian = 0.12
    static let capacity = 6000

    init(scale: Double, size: CGSize) {
        split = 9 * scale
        radius = 44 * scale
        maximumStep = 1.9 * scale
        margin = 40 * scale
        self.size = size
    }
}

/// The ring's nodes in flat buffers, and a grid of half-radius cells rebuilt every step by
/// counting sort, so the nodes near a node lie in a few runs of the sorted copy, one per
/// grid row. Each pair of nodes is visited once: lanes take turns at the nodes in sorted
/// order and look only ahead of them (the rest of their own row of cells, then the next two
/// rows), adding each push to both nodes in their own accumulator. Then the lanes move their
/// share of the nodes, summing the four accumulators in a fixed order. The random nudges
/// come from a hash of the step and node, so nothing depends on which lane runs first.
private final class DifferentialGrowth {
    private let rules: GrowthRules
    private let grid: GrowthGrid
    private(set) var count: Int
    private var positions: (x: LaneBuffer<Double>, y: LaneBuffer<Double>)
    private var moved: (x: LaneBuffer<Double>, y: LaneBuffer<Double>)
    private let sorted: GrowthSorted
    private let starts: LaneBuffer<Int32>
    /// Per lane, `capacity` (x, y) pushes, indexed by sorted slot.
    private let pushes: LaneBuffer<Double>
    private let splits: LaneBuffer<UInt8>

    init(ring: [CGPoint], size: CGSize, scale: Double) {
        rules = GrowthRules(scale: scale, size: size)
        let cell = rules.radius / 2
        grid = GrowthGrid(
            columns: Int((size.width / cell).rounded(.up)), rows: Int((size.height / cell).rounded(.up)), cell: cell
        )
        let capacity = GrowthRules.capacity
        positions = (LaneBuffer(zeroed: capacity), LaneBuffer(zeroed: capacity))
        moved = (LaneBuffer(zeroed: capacity), LaneBuffer(zeroed: capacity))
        sorted = GrowthSorted(capacity: capacity)
        starts = LaneBuffer(zeroed: grid.columns * grid.rows + 1)
        pushes = LaneBuffer(zeroed: RenderLanes.count * capacity * 2)
        splits = LaneBuffer(zeroed: capacity)
        count = ring.count
        for (node, point) in ring.enumerated() {
            (positions.x.base[node], positions.y.base[node]) = (point.x, point.y)
        }
    }

    deinit {
        for buffer in [positions.x, positions.y, moved.x, moved.y, pushes] {
            buffer.deallocate()
        }
        sorted.deallocate()
        starts.deallocate()
        splits.deallocate()
    }

    /// Grows for `steps` steps; returns the ring every `every` steps, then as it ends.
    func run(steps: Int, every: Int, food: SampledField, using rng: inout SeededGenerator) -> [[CGPoint]] {
        var stages: [[CGPoint]] = []
        for step in 0 ..< steps {
            sortIntoGrid()
            move(seed: rng.next())
            if count < GrowthRules.capacity { split(food: food, using: &rng) }
            if step % every == 0 { stages.append(ring) }
        }
        stages.append(ring)
        return stages
    }

    private var ring: [CGPoint] {
        let (xs, ys) = (positions.x.base, positions.y.base)
        return [CGPoint](unsafeUninitializedCapacity: count) { points, initialized in
            var node = 0
            while node < count {
                points[node] = CGPoint(x: xs[node], y: ys[node])
                node += 1
            }
            initialized = count
        }
    }

    /// Counting sort by grid cell into `sorted`: cell c's nodes end up in
    /// `starts[c] ..< starts[c + 1]`.
    private func sortIntoGrid() {
        let cellCount = grid.columns * grid.rows
        let (xs, ys, cells, starts) = (positions.x.base, positions.y.base, sorted.cellOfNode.base, starts.base)
        memset(starts, 0, (cellCount + 1) * MemoryLayout<Int32>.stride)
        var node = 0
        while node < count {
            let cell = grid.cell(xs[node], ys[node])
            cells[node] = Int32(cell)
            starts[cell] += 1
            node += 1
        }
        // Running totals put each cell's start at the end of its run…
        var cell = 1
        while cell < cellCount {
            starts[cell] += starts[cell - 1]
            cell += 1
        }
        starts[cellCount] = Int32(count)
        // …and filling every run from its end moves it back to the start.
        node = count - 1
        while node >= 0 {
            let cell = Int(cells[node])
            starts[cell] -= 1
            let slot = Int(starts[cell])
            (sorted.x.base[slot], sorted.y.base[slot]) = (xs[node], ys[node])
            (sorted.id.base[slot], sorted.cell.base[slot]) = (Int32(node), Int32(cell))
            sorted.slotOfNode.base[node] = Int32(slot)
            node -= 1
        }
    }
}

/// The grid of half-radius cells over unit space.
private struct GrowthGrid: Sendable {
    let columns: Int
    let rows: Int
    let cell: Double

    func cell(_ x: Double, _ y: Double) -> Int {
        let column = Int(x / cell), row = Int(y / cell)
        let clampedColumn = column < 0 ? 0 : column >= columns ? columns - 1 : column
        let clampedRow = row < 0 ? 0 : row >= rows ? rows - 1 : row
        return clampedRow * columns + clampedColumn
    }
}

/// The nodes in grid order, and the way back.
private struct GrowthSorted: Sendable {
    let x: LaneBuffer<Double>
    let y: LaneBuffer<Double>
    let id: LaneBuffer<Int32>
    let cell: LaneBuffer<Int32>
    let cellOfNode: LaneBuffer<Int32>
    let slotOfNode: LaneBuffer<Int32>

    init(capacity: Int) {
        (x, y) = (LaneBuffer(zeroed: capacity), LaneBuffer(zeroed: capacity))
        (id, cell) = (LaneBuffer(zeroed: capacity), LaneBuffer(zeroed: capacity))
        (cellOfNode, slotOfNode) = (LaneBuffer(zeroed: capacity), LaneBuffer(zeroed: capacity))
    }

    func deallocate() {
        x.deallocate()
        y.deallocate()
        for buffer in [id, cell, cellOfNode, slotOfNode] {
            buffer.deallocate()
        }
    }
}

private extension DifferentialGrowth {
    /// One step of forces on the lanes, from `positions` into `moved`, then swapped back.
    func move(seed: UInt64) {
        let capacity = GrowthRules.capacity
        for lane in 0 ..< RenderLanes.count {
            memset(pushes.base + lane * capacity * 2, 0, count * 2 * MemoryLayout<Double>.stride)
        }
        let state = GrowthStep(
            rules: rules, grid: grid, count: count, seed: seed, positions: positions, moved: moved,
            sorted: sorted, starts: starts, pushes: pushes
        )
        RenderLanes.split(count) { lane, homes in
            state.push(from: homes, into: state.pushes.base + lane * capacity * 2)
        }
        RenderLanes.split(count) { _, nodes in
            state.move(nodes)
        }
        (positions, moved) = (moved, positions)
    }

    /// Splits every edge longer than `split`, and a few random edges more where `food` is
    /// rich (more likely the richer), inserting their midpoints, nudged, into the ring.
    func split(food: SampledField, using rng: inout SeededGenerator) {
        let (xs, ys, flags) = (positions.x.base, positions.y.base, splits.base)
        let state = (count: count, xs: positions.x, ys: positions.y, flags: splits, split: rules.split)
        RenderLanes.split(count) { _, edges in
            for edge in edges {
                let next = edge + 1 == state.count ? 0 : edge + 1
                let dx = state.xs.base[next] - state.xs.base[edge], dy = state.ys.base[next] - state.ys.base[edge]
                state.flags.base[edge] = dx * dx + dy * dy > state.split * state.split ? 1 : 0
            }
        }
        for _ in 0 ..< max(3, count / 40) {
            let edge = Int(rng.next() % UInt64(count)), next = (edge + 1) % count
            let richness = food.value((xs[edge] + xs[next]) / 2, (ys[edge] + ys[next]) / 2)
            if Double(rng.next() >> 11) * 0x1p-53 < richness * richness * 1.6 { flags[edge] = 1 }
        }
        insertMidpoints(using: &rng)
    }

    /// Rebuilds the ring with a nudged midpoint after every flagged edge, copying the runs
    /// between them whole, up to the node cap.
    private func insertMidpoints(using rng: inout SeededGenerator) {
        let (xs, ys, flags) = (positions.x.base, positions.y.base, splits.base)
        let (outX, outY) = (moved.x.base, moved.y.base)
        var room = GrowthRules.capacity - count, written = 0, copied = 0, edge = 0
        while edge < count, room > 0 {
            if flags[edge] == 1 {
                let run = edge + 1 - copied
                memcpy(outX + written, xs + copied, run * MemoryLayout<Double>.stride)
                memcpy(outY + written, ys + copied, run * MemoryLayout<Double>.stride)
                written += run
                copied = edge + 1
                let next = edge + 1 == count ? 0 : edge + 1
                outX[written] = (xs[edge] + xs[next]) / 2 + rng.between(-0.3, 0.3)
                outY[written] = (ys[edge] + ys[next]) / 2 + rng.between(-0.3, 0.3)
                written += 1
                room -= 1
            }
            edge += 1
        }
        guard written > 0 else { return }
        memcpy(outX + written, xs + copied, (count - copied) * MemoryLayout<Double>.stride)
        memcpy(outY + written, ys + copied, (count - copied) * MemoryLayout<Double>.stride)
        count = written + count - copied
        (positions, moved) = (moved, positions)
    }
}

/// A push on one node, summed over its neighbors.
private typealias GrowthPush = (x: Double, y: Double)

/// What the lanes need for a step of forces.
private struct GrowthStep: Sendable {
    let rules: GrowthRules
    let grid: GrowthGrid
    let count: Int
    let seed: UInt64
    let positions: (x: LaneBuffer<Double>, y: LaneBuffer<Double>)
    let moved: (x: LaneBuffer<Double>, y: LaneBuffer<Double>)
    let sorted: GrowthSorted
    let starts: LaneBuffer<Int32>
    let pushes: LaneBuffer<Double>

    /// The pushes between each node in `homes` (sorted slots) and the nodes after it in the
    /// rest of its row of cells and the two rows below, added to both in `lane`'s
    /// accumulator: every pair of nodes in reach is met exactly once.
    func push(from homes: Range<Int>, into lane: UnsafeMutablePointer<Double>) {
        let (columns, rows, starts) = (grid.columns, grid.rows, starts.base)
        var home = homes.lowerBound
        while home < homes.upperBound {
            let cell = Int(sorted.cell.base[home]), column = cell % columns, row = cell / columns
            let first = column - 2 < 0 ? 0 : column - 2, last = column + 2 >= columns ? columns - 1 : column + 2
            var total: GrowthPush = (0, 0)
            meet(home, slots: home + 1, Int(starts[row * columns + last + 1]), lane: lane, total: &total)
            var below = row + 1
            while below <= row + 2, below < rows {
                let start = Int(starts[below * columns + first]), end = Int(starts[below * columns + last + 1])
                meet(home, slots: start, end, lane: lane, total: &total)
                below += 1
            }
            lane[home * 2] += total.x
            lane[home * 2 + 1] += total.y
            home += 1
        }
    }

    /// Pushes `home` and every node in slots `start ..< end` apart, if they're within the
    /// radius and more than two steps apart along the ring: 1.2·(1 − d/r) each way.
    private func meet(
        _ home: Int, slots start: Int, _ end: Int, lane: UnsafeMutablePointer<Double>, total: inout GrowthPush
    ) {
        let (sortedX, sortedY, ids) = (sorted.x.base, sorted.y.base, sorted.id.base)
        let radius = rules.radius, reach = radius * radius, x = sortedX[home], y = sortedY[home]
        let node = Int(ids[home])
        var slot = start
        while slot < end {
            let dx = x - sortedX[slot], dy = y - sortedY[slot], squared = dx * dx + dy * dy
            if squared < reach, squared > 1e-6 {
                let other = Int(ids[slot])
                var apart = node > other ? node - other : other - node
                if apart > count - apart { apart = count - apart }
                if apart > 2 {
                    let strength = GrowthRules.repulsion * (1 / squared.squareRoot() - 1 / radius)
                    total.x += dx * strength
                    total.y += dy * strength
                    lane[slot * 2] -= dx * strength
                    lane[slot * 2 + 1] -= dy * strength
                }
            }
            slot += 1
        }
    }

    /// Moves `nodes`: toward their neighbors' midpoint, by the summed pushes, a random nudge
    /// and the soft walls, clamped to the maximum step.
    func move(_ nodes: Range<Int>) {
        let (xs, ys, slots) = (positions.x.base, positions.y.base, sorted.slotOfNode.base)
        let laneStride = GrowthRules.capacity * 2
        var node = nodes.lowerBound
        while node < nodes.upperBound {
            let x = xs[node], y = ys[node], slot = Int(slots[node]) * 2
            let before = node == 0 ? count - 1 : node - 1, after = node + 1 == count ? 0 : node + 1
            let push = pushes.base + slot
            let pushX = push[0] + push[laneStride] + push[laneStride * 2] + push[laneStride * 3]
            let pushY = push[1] + push[laneStride + 1] + push[laneStride * 2 + 1] + push[laneStride * 3 + 1]
            let nudge = scrambled(seed &+ UInt64(node) &* 0x9E37_79B9_7F4A_7C15)
            var forceX = ((xs[before] + xs[after]) / 2 - x) * GrowthRules.attraction + pushX
                + (Double(nudge &>> 32) * 0x1p-31 - 1) * GrowthRules.brownian
            var forceY = ((ys[before] + ys[after]) / 2 - y) * GrowthRules.attraction + pushY
                + (Double(nudge & 0xFFFF_FFFF) * 0x1p-31 - 1) * GrowthRules.brownian
            let margin = rules.margin, right = rules.size.width - margin, bottom = rules.size.height - margin
            if x < margin { forceX += (margin - x) * 0.05 }
            if x > right { forceX -= (x - right) * 0.05 }
            if y < margin { forceY += (margin - y) * 0.05 }
            if y > bottom { forceY -= (y - bottom) * 0.05 }
            let length = (forceX * forceX + forceY * forceY).squareRoot()
            let limit = length > rules.maximumStep ? rules.maximumStep / length : 1
            moved.x.base[node] = x + forceX * limit
            moved.y.base[node] = y + forceY * limit
            node += 1
        }
    }
}
