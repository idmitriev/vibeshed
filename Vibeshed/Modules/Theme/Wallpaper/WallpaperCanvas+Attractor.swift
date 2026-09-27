import CoreGraphics
import Foundation

/// A Clifford strange attractor plotted as a density map.
extension WallpaperCanvas {
    /// Coefficients (a, b, c, d) of Clifford attractors that spread into good figures.
    private static let cliffordPresets: [[Double]] = [
        [-1.4, 1.6, 1.0, 0.7], [1.6, -0.6, -1.2, 1.6], [1.7, 1.7, 0.06, 1.2],
        [1.3, 1.7, 0.5, 1.4], [-1.7, 1.3, -0.1, -1.2], [-1.8, -2.0, -0.5, -0.9],
    ]

    /// Millions of points of a Clifford attractor counted into a histogram and shaded by log
    /// density. The histogram is capped at 1200 columns and scaled up, so the cost doesn't
    /// grow with the display.
    mutating func paintAttractor() {
        let coefficients = rng.pick(Self.cliffordPresets).map { $0 + rng.between(-0.02, 0.02) }
        var figure = CliffordAttractor(coefficients)
        let mirror: Double = rng.unit() < 0.5 ? 1 : -1
        let columns = min(Int(width), 1200), rows = max(1, Int((Double(columns) * Double(height / width)).rounded()))
        let bounds = figure.settle()
        let scale = min(
            Double(columns) * 0.72 / (bounds.maxX - bounds.minX), Double(rows) * 0.84 / (bounds.maxY - bounds.minY)
        )
        let density = AttractorDensity(
            columns: columns, rows: rows,
            origin: (
                x: Double(columns) * rng.between(0.47, 0.55) - mirror * (bounds.minX + bounds.maxX) / 2 * scale,
                y: Double(rows) / 2 - (bounds.minY + bounds.maxY) / 2 * scale
            ),
            scale: (x: mirror * scale, y: scale)
        )
        let starts = (0 ..< AttractorDensity.lanes).map { _ in figure.skip(1000) }
        // About three million points at 960×600, the same density at other sizes.
        density.gather(figure, from: starts, points: min(max(Int(5.2 * Double(columns * rows)), 50000), 4_000_000))
        let pixels = density.shade(attractorRamp())
        guard let image = bitmapImage(columns: columns, rows: rows, pixels: pixels) else { return fill(base) }
        context.draw(image, in: rect)
    }

    /// 1024 density levels → RGB, from the background through a neighbouring hue and the
    /// accent to a highlight (dark themes) or ink (light themes).
    private func attractorRamp() -> [UInt8] {
        let hues = harmony(3)
        let low = muted(hues.cycling(1), isDark ? 0.3 : 0.2), middle = hues[0]
        let high = isDark ? hues[0].mix(.white, 0.7) : hues[0].mix(.black, 0.5)
        return (0 ..< 1024).flatMap { step -> [UInt8] in
            let level = Double(step) / 1023
            let tone = level < 0.5 ? low.mix(middle, level * 2) : middle.mix(high, (level - 0.5) * 2)
            let color = base.mix(tone, smoothstep(0, 0.45, level))
            return [UInt8(color.red8), UInt8(color.green8), UInt8(color.blue8)]
        }
    }
}

/// x' = sin(α·y) + γ·cos(α·x), y' = sin(β·x) + δ·cos(β·y) — Pickover's (a, b, c, d).
private struct CliffordAttractor {
    let alpha: Double
    let beta: Double
    let gamma: Double
    let delta: Double
    var x = 0.1
    var y = 0.1

    init(_ coefficients: [Double]) {
        alpha = coefficients[0]
        beta = coefficients[1]
        gamma = coefficients[2]
        delta = coefficients[3]
    }

    mutating func advance() {
        (x, y) = (sin(alpha * y) + gamma * cos(alpha * x), sin(beta * x) + delta * cos(beta * y))
    }

    /// Moves `steps` along the orbit and returns where it ends up.
    mutating func skip(_ steps: Int) -> (x: Double, y: Double) {
        for _ in 0 ..< steps { advance() }
        return (x, y)
    }

    /// Runs past the transient and measures the figure's extent.
    mutating func settle() -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        _ = skip(100)
        var bounds = (minX: x, maxX: x, minY: y, maxY: y)
        for _ in 0 ..< 50000 {
            advance()
            bounds = (min(bounds.minX, x), max(bounds.maxX, x), min(bounds.minY, y), max(bounds.maxY, y))
        }
        return bounds
    }
}

/// An attractor's density on a `columns × rows` grid, gathered on four threads. Each lane
/// follows its own orbit into its own slice of one buffer and the slices are summed, so the
/// totals don't depend on scheduling and renders stay reproducible. The per-cell passes run
/// on the lanes too: debug builds (what `make install` ships) make a million-cell loop slow.
/// Lanes only ever write their own slice, which is what makes the shared buffers safe.
private final class AttractorDensity: @unchecked Sendable {
    /// Fixed, so a render doesn't depend on the machine. Four measured faster than eight
    /// and matches the performance cores of the smallest Apple silicon chips.
    static let lanes = 4

    private let columns: Int
    private let rows: Int
    private let origin: (x: Double, y: Double)
    private let scale: (x: Double, y: Double)
    private let counts: UnsafeMutablePointer<UInt32>
    private let pixels: UnsafeMutablePointer<UInt8>
    private let maxima: UnsafeMutablePointer<UInt32>
    private var cells: Int { columns * rows }

    init(columns: Int, rows: Int, origin: (x: Double, y: Double), scale: (x: Double, y: Double)) {
        self.columns = columns
        self.rows = rows
        self.origin = origin
        self.scale = scale
        counts = .allocate(capacity: columns * rows * Self.lanes)
        memset(counts, 0, columns * rows * Self.lanes * MemoryLayout<UInt32>.stride)
        pixels = .allocate(capacity: columns * rows * 4)
        maxima = .allocate(capacity: Self.lanes)
        memset(maxima, 0, Self.lanes * MemoryLayout<UInt32>.stride)
    }

    deinit {
        counts.deallocate()
        pixels.deallocate()
        maxima.deallocate()
    }

    /// Follows `points` points of `figure`'s orbit, split across the lanes from `starts`, and
    /// sums the lanes into the first one's slice.
    func gather(_ figure: CliffordAttractor, from starts: [(x: Double, y: Double)], points: Int) {
        DispatchQueue.concurrentPerform(iterations: Self.lanes) { lane in
            self.trace(figure, from: starts[lane], points: points / Self.lanes, into: self.counts + lane * self.cells)
        }
        DispatchQueue.concurrentPerform(iterations: Self.lanes) { slice in
            var densest: UInt32 = 0
            for cell in self.cellRange(slice) {
                for lane in 1 ..< Self.lanes {
                    self.counts[cell] &+= self.counts[lane * self.cells + cell]
                }
                densest = max(densest, self.counts[cell])
            }
            self.maxima[slice] = densest
        }
    }

    /// RGBX pixels, row 0 at the top, shaded by log density through `ramp` (1024 RGB
    /// triples from empty to densest).
    func shade(_ ramp: [UInt8]) -> [UInt8] {
        let peak = log1p(Double(max((0 ..< Self.lanes).map { maxima[$0] }.max() ?? 1, 1)))
        let offsets = (0 ..< 4096).map { Self.offset(count: $0, peak: peak) } // most cells see few points
        DispatchQueue.concurrentPerform(iterations: Self.lanes) { slice in
            for cell in self.cellRange(slice) {
                let count = Int(self.counts[cell])
                let offset = count < offsets.count ? offsets[count] : Self.offset(count: count, peak: peak)
                self.pixels[cell * 4] = ramp[offset]
                self.pixels[cell * 4 + 1] = ramp[offset + 1]
                self.pixels[cell * 4 + 2] = ramp[offset + 2]
                self.pixels[cell * 4 + 3] = 255
            }
        }
        return Array(UnsafeBufferPointer(start: pixels, count: cells * 4))
    }

    /// Where `count` lands in the 1024-level ramp, as an offset into its RGB triples.
    private static func offset(count: Int, peak: Double) -> Int {
        count == 0 ? 0 : Int(min(pow(log1p(Double(count)) / peak, 0.9), 1) * 1023) * 3
    }

    private func cellRange(_ slice: Int) -> Range<Int> {
        slice * cells / Self.lanes ..< (slice + 1) * cells / Self.lanes
    }

    /// One lane's orbit. This runs millions of times and debug builds don't inline, so
    /// `CliffordAttractor.advance` is written out here and a `while` loop stands in for a
    /// range iterator.
    private func trace(
        _ figure: CliffordAttractor, from start: (x: Double, y: Double), points: Int,
        into lane: UnsafeMutablePointer<UInt32>
    ) {
        let (alpha, beta, gamma, delta) = (figure.alpha, figure.beta, figure.gamma, figure.delta)
        let (originX, originY, scaleX, scaleY) = (origin.x, origin.y, scale.x, scale.y)
        let (width, right, bottom) = (columns, Double(columns), Double(rows))
        var (x, y) = start, remaining = points
        while remaining > 0 {
            remaining -= 1
            (x, y) = (sin(alpha * y) + gamma * cos(alpha * x), sin(beta * x) + delta * cos(beta * y))
            let column = originX + scaleX * x, row = originY + scaleY * y
            if column >= 0, row >= 0, column < right, row < bottom {
                (lane + Int(row) * width + Int(column)).pointee &+= 1
            }
        }
    }
}
