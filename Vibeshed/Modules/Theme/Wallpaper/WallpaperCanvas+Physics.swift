import Accelerate
import CoreGraphics
import Foundation

/// Physics: sand on a vibrating plate, settling into Chladni figures. The grains are
/// simulated on the render lanes and stamped straight into coverage masks, so a few hundred
/// thousand of them don't take a few hundred thousand Core Graphics calls.
extension WallpaperCanvas {
    /// Sand on a vibrating plate (Ernst Chladni, *Entdeckungen über die Theorie des
    /// Klanges*, 1787): grains slide down the slope of the plate's displacement squared and
    /// gather on the nodal lines, where it stands still, shaken loose wherever it moves. The
    /// whole screen is the plate, vibrating in two mirror-twin modes of a square plate,
    /// cos(nπx)·cos(mπy) ± cos(mπx)·cos(nπy). One grain in nineteen is colored sand.
    mutating func paintChladni() {
        let first = 2 + rng.int(below: 6)
        var second = 2 + rng.int(below: 6)
        while second == first {
            second = 2 + rng.int(below: 6)
        }
        let plate = ChladniPlate(
            modes: (Double(first), Double(second)), sign: rng.unit() < 0.5 ? -1 : 1, aspect: Double(width / height)
        )
        // About one grain per 25 pixels, so a thumbnail stays as cheap as it is small.
        let sand = ChladniSand(count: min(max(Int(width * height / 25), 20000), 300_000))
        defer { sand.deallocate() }
        sand.settle(on: plate, steps: 60, seeds: (0 ..< RenderLanes.count).map { _ in rng.next() })
        fill(base)
        let dot = max(0.9 * unit, 1.3)
        let grain = isDark ? palette.foreground.mix(harmony(1)[0], 0.15) : palette.foreground
        paintSand(sand, stamp: GrainStamp(every: 1, size: dot, opacity: isDark ? 0.5 : 0.45), color: grain)
        paintSand(sand, stamp: GrainStamp(every: 19, size: dot * 1.4, opacity: 0.85), color: palette.accent)
    }

    /// Stamps the grains into a coverage mask, each a square compositing over the ones
    /// before it like a separately painted dot, then fills `color` through the mask.
    private func paintSand(_ sand: ChladniSand, stamp: GrainStamp, color: ThemeColor) {
        let mask = CoverageMask(columns: Int(width), rows: Int(height))
        defer { mask.coverage.deallocate() }
        let scale = Double(height) // plate units to pixels
        RenderLanes.split(mask.rows) { _, band in
            sand.stamp(stamp, scale: scale, into: mask, rows: band)
        }
        guard let image = mask.image() else { return }
        context.saveGState()
        context.clip(to: rect, mask: image)
        fill(color)
        context.restoreGState()
    }
}

/// The plate's displacement f(x, y), x across `0...aspect` and y down `0...1`.
struct ChladniPlate: Sendable {
    let modes: (n: Double, m: Double)
    let sign: Double
    let aspect: Double

    func value(x: Double, y: Double) -> Double {
        cos(modes.n * .pi * x) * cos(modes.m * .pi * y) + sign * cos(modes.m * .pi * x) * cos(modes.n * .pi * y)
    }

    /// Moves one grain `steps` times down the slope of f², with a shake that's strongest
    /// where the plate moves most. The gradient is analytic, sharing its cosines with f.
    func settle(x: inout Double, y: inout Double, steps: Int, random: inout UInt64) {
        let (modeN, modeM) = modes
        var (sinNX, cosNX, sinMX, cosMX, sinNY, cosNY, sinMY, cosMY) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        var step = 0
        while step < steps {
            __sincospi(modeN * x, &sinNX, &cosNX)
            __sincospi(modeM * x, &sinMX, &cosMX)
            __sincospi(modeN * y, &sinNY, &cosNY)
            __sincospi(modeM * y, &sinMY, &cosMY)
            let value = cosNX * cosMY + sign * cosMX * cosNY
            let slopeX = -.pi * (modeN * sinNX * cosMY + sign * modeM * sinMX * cosNY)
            let slopeY = -.pi * (modeM * cosNX * sinMY + sign * modeN * cosMX * sinNY)
            let magnitude = value < 0 ? -value : value
            let shake = 0.0014 * (magnitude < 1 ? magnitude : 1)
            let bits = ChladniSand.scramble(&random)
            let jitterX = (Double(bits &>> 32) * 0x1p-31 - 1) * shake
            let jitterY = (Double(bits & 0xFFFF_FFFF) * 0x1p-31 - 1) * shake
            let nextX = x - 0.0008 * value * slopeX + jitterX, nextY = y - 0.0008 * value * slopeY + jitterY
            x = nextX < 0 ? 0 : nextX > aspect ? aspect : nextX
            y = nextY < 0 ? 0 : nextY > 1 ? 1 : nextY
            step += 1
        }
    }
}

/// Grain positions in plate units, split across the lanes by index.
private struct ChladniSand: Sendable {
    let xs: LaneBuffer<Double>
    let ys: LaneBuffer<Double>

    init(count: Int) {
        xs = LaneBuffer(zeroed: count)
        ys = LaneBuffer(zeroed: count)
    }

    func deallocate() {
        xs.deallocate()
        ys.deallocate()
    }

    /// Scatters the grains uniformly and lets each settle. Every lane draws from its own
    /// SplitMix64 stream, seeded before the lanes start.
    func settle(on plate: ChladniPlate, steps: Int, seeds: [UInt64]) {
        RenderLanes.split(xs.count) { lane, range in
            var random = seeds[lane], grain = range.lowerBound
            while grain < range.upperBound {
                let bits = Self.scramble(&random)
                var x = Double(bits &>> 32) * 0x1p-32 * plate.aspect, y = Double(bits & 0xFFFF_FFFF) * 0x1p-32
                plate.settle(x: &x, y: &y, steps: steps, random: &random)
                (xs.base[grain], ys.base[grain]) = (x, y)
                grain += 1
            }
        }
    }

    /// Stamps every `stamp.every`th grain into `mask`, touching only `rows`.
    func stamp(_ stamp: GrainStamp, scale: Double, into mask: CoverageMask, rows: Range<Int>) {
        let half = stamp.size / 2, top = Double(rows.lowerBound) - half, bottom = Double(rows.upperBound) + half
        var grain = 0
        while grain < xs.count {
            let y = ys.base[grain] * scale
            if y > top, y < bottom {
                mask.stamp(x: xs.base[grain] * scale, y: y, size: stamp.size, opacity: stamp.opacity, rows: rows)
            }
            grain += stamp.every
        }
    }

    /// SplitMix64's next output, without the generic plumbing `SeededGenerator` goes
    /// through, which debug builds don't specialize.
    static func scramble(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        return scrambled(state)
    }
}

/// How one pass of grains is drawn: every `every`th grain, as a `size`-pixel square.
private struct GrainStamp {
    let every: Int
    let size: Double
    let opacity: Double
}

/// Per-pixel opacity over the whole canvas, row 0 at the top.
private struct CoverageMask: Sendable {
    let coverage: LaneBuffer<Float>
    let columns: Int
    let rows: Int

    init(columns: Int, rows: Int) {
        coverage = LaneBuffer(zeroed: columns * rows)
        self.columns = columns
        self.rows = rows
    }

    /// Composites a `size`-pixel square centered on (x, y) at `opacity` (source over, by the
    /// area it covers of each pixel), within `rows` only.
    func stamp(x: Double, y: Double, size: Double, opacity: Double, rows band: Range<Int>) {
        let half = size / 2, (left, right, top, bottom) = (x - half, x + half, y - half, y + half)
        let firstRow = Int(floor(top)), lastRow = Int(ceil(bottom)) - 1
        let firstColumn = Int(floor(left)), lastColumn = Int(ceil(right)) - 1
        var row = firstRow < band.lowerBound ? band.lowerBound : firstRow
        while row <= lastRow, row < band.upperBound {
            let rowTop = Double(row)
            let coverY = (bottom < rowTop + 1 ? bottom : rowTop + 1) - (top > rowTop ? top : rowTop)
            var column = firstColumn < 0 ? 0 : firstColumn
            while column <= lastColumn, column < columns {
                let edge = Double(column)
                let coverX = (right < edge + 1 ? right : edge + 1) - (left > edge ? left : edge)
                let pixel = coverage.base + row * columns + column
                pixel.pointee += (1 - pixel.pointee) * Float(opacity * coverX * coverY)
                column += 1
            }
            row += 1
        }
    }

    /// The mask as an 8-bit gray image, for `CGContext.clip(to:mask:)`.
    func image() -> CGImage? {
        guard let bytes = malloc(columns * rows) else { return nil }
        var source = vImage_Buffer(
            data: coverage.base, height: vImagePixelCount(rows), width: vImagePixelCount(columns),
            rowBytes: columns * MemoryLayout<Float>.stride
        )
        var destination = vImage_Buffer(
            data: bytes, height: vImagePixelCount(rows), width: vImagePixelCount(columns), rowBytes: columns
        )
        let converted = vImageConvert_PlanarFtoPlanar8(&source, &destination, 1, 0, vImage_Flags(kvImageNoFlags))
        guard converted == kvImageNoError,
              let provider = CGDataProvider(
                  dataInfo: nil, data: bytes, size: columns * rows,
                  releaseData: { _, data, _ in free(UnsafeMutableRawPointer(mutating: data)) }
              )
        else {
            free(bytes)
            return nil
        }
        return CGImage(
            width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: columns,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
