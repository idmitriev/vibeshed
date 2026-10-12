import CoreGraphics
import Foundation

/// Fields computed pixel by pixel at full device resolution, on the render lanes: stripes
/// and a sun bent by a gravitational lens, and a complex function's phase portrait. Their
/// edges are filtered analytically, one pixel soft, instead of supersampled.
///
/// Lens is adapted from gart (https://github.com/igr/gart), © 2022 Igor Spasić, BSD 2-Clause License.
extension WallpaperCanvas {
    // MARK: - Lens

    /// Tilted stripes and a sun behind a black hole, seen through its gravitational lens
    /// (after gart's SF14). Every ray bends toward the hole by e²/r, so the stripes wrap
    /// around the Einstein ring and the sun shows twice: a long arc outside the ring and a
    /// short one inside. The lens's Jacobian gives each pixel's stretch, which sets the
    /// width of its box filter.
    mutating func paintLens() {
        let einstein = 240 * Double(unit) * rng.between(0.85, 1.15)
        let center = (x: Double(width) * rng.between(0.3, 0.7), y: Double(height) * rng.between(0.32, 0.68))
        let bearing = rng.between(0, 2 * .pi), offset = rng.between(0.3, 0.7) * einstein
        let phase = rng.unit()
        let tilt = rng.between(18, 42) * (rng.unit() < 0.5 ? 1 : -1) * .pi / 180
        let ink = palette.foreground.mix(base, isDark ? 0.18 : 0.1)
        let lens = GravitationalLens(
            center: center, einstein: einstein,
            sun: (x: center.x + cos(bearing) * offset, y: center.y + sin(bearing) * offset, radius: 0.31 * einstein),
            stripes: (pitch: 31 * Double(unit), phase: phase, normal: (x: -sin(tilt), y: cos(tilt))),
            // Ground, stripe ink, sun, hole. On light themes the hole takes the ink, so it
            // still reads as black.
            tones: [base, ink, palette.accent, isDark ? base : ink].map(PixelTone.init)
        )
        let columns = Int(width)
        paintRows { row, pixels in lens.shade(row: row, columns: columns, into: pixels) }
    }

    // MARK: - Complex

    /// An enhanced phase portrait of a complex function, after Elias Wegert's *Visual
    /// Complex Functions* (2012): the argument of f(z) goes once around a ring of palette
    /// colors, log₂|f| adds shaded bands, rings that crowd in on every zero and pole, and
    /// twelve faint lines mark the phase. Zeros and poles become pinwheels.
    mutating func paintComplex() {
        let function = rng.pick(PhasePortrait.Function.allCases)
        let offset = (x: rng.between(-0.3, 0.3) * function.span, y: rng.between(-0.2, 0.2) * function.span)
        let hues = harmony(4, keepingTwin: true)
        let stops = isDark
            ? [hues[0], muted(hues.cycling(1), 0.2), muted(hues.cycling(2), 0.35), muted(hues.cycling(3), 0.2)]
            : zip(0 ..< 4, [0.2, 0.35, 0.5, 0.35]).map { hues.cycling($0).mix(palette.background, $1) }
        // The ring as RGB triples in raw memory: the per-pixel lookup stays a plain load.
        let ring = LaneBuffer<Double>(zeroed: PhasePortrait.ringSize * 3)
        defer { ring.deallocate() }
        for step in 0 ..< PhasePortrait.ringSize {
            let position = Double(step) / Double(PhasePortrait.ringSize) * Double(stops.count)
            let index = Int(position)
            let tone = PixelTone(stops.cycling(index).mix(
                stops.cycling(index + 1),
                smoothstep(0, 1, position - Double(index))
            ))
            (ring.base[step * 3], ring.base[step * 3 + 1], ring.base[step * 3 + 2]) = (tone.red, tone.green, tone.blue)
        }
        let portrait = PhasePortrait(
            function: function, scale: Double(height) / function.span,
            center: (x: Double(width) / 2, y: Double(height) / 2), offset: offset,
            ring: ring, ground: PixelTone(base), isDark: isDark
        )
        let columns = Int(width)
        paintRows { row, pixels in portrait.shade(row: row, columns: columns, into: pixels) }
    }
}

/// A point lens over a plane of stripes and a sun, in device pixels with y down.
private struct GravitationalLens: Sendable {
    let center: (x: Double, y: Double)
    let einstein: Double
    let sun: (x: Double, y: Double, radius: Double)
    let stripes: (pitch: Double, phase: Double, normal: (x: Double, y: Double))
    let tones: [PixelTone]

    /// The share of each stripe period that's inked.
    private static let duty = 0.32

    func shade(row: Int, columns: Int, into pixels: UnsafeMutablePointer<UInt8>) {
        let (ground, ink, bold, hole) = (tones[0], tones[1], tones[2], tones[3])
        let holeRadius = einstein * 0.38
        let y = Double(row) + 0.5, dy = y - center.y
        var column = 0
        while column < columns {
            let x = Double(column) + 0.5, dx = x - center.x, squared = dx * dx + dy * dy
            let dark = clampUnit(0.5 - (squared.squareRoot() - holeRadius))
            var seen = (band: 0.0, sun: 0.0)
            if dark < 1 { seen = sample(x: x, y: y, dx: dx, dy: dy) }
            ground.mixed(ink, seen.band).mixed(bold, seen.sun).mixed(hole, dark).write(to: pixels + column * 4)
            column += 1
        }
    }

    /// How much stripe ink and sun the ray through pixel (x, y) lands on, each box-filtered
    /// over the pixel's footprint on the source plane.
    private func sample(x: Double, y: Double, dx: Double, dy: Double) -> (band: Double, sun: Double) {
        let squared = dx * dx + dy * dy
        let bend = einstein * einstein / squared, change = 2 * bend / squared
        let sourceX = x - bend * dx, sourceY = y - bend * dy
        // The Jacobian of the deflection (symmetric).
        let j11 = 1 - (bend - change * dx * dx), j22 = 1 - (bend - change * dy * dy), j12 = change * dx * dy
        let normal = stripes.normal
        let across = (sourceX * normal.x + sourceY * normal.y) / stripes.pitch + stripes.phase
        let stretchX = j11 * normal.x + j12 * normal.y, stretchY = j12 * normal.x + j22 * normal.y
        let band = Self.stripe(
            across,
            footprint: (stretchX * stretchX + stretchY * stretchY).squareRoot() / stripes.pitch
        )
        let fromSunX = sourceX - sun.x, fromSunY = sourceY - sun.y
        let distance = (fromSunX * fromSunX + fromSunY * fromSunY).squareRoot()
        let radialX = j11 * fromSunX + j12 * fromSunY, radialY = j12 * fromSunX + j22 * fromSunY
        let stretch = (radialX * radialX + radialY * radialY).squareRoot() / distance
        let lit = distance < 1e-4 || stretch < 1e-6
            ? (distance < sun.radius ? 1 : 0)
            : clampUnit(0.5 - (distance - sun.radius) / stretch)
        return (band, lit)
    }

    /// The inked share of `[value − footprint/2, value + footprint/2]` (in stripe periods):
    /// the exact box filter of a square wave, which antialiases without supersampling.
    private static func stripe(_ value: Double, footprint: Double) -> Double {
        if footprint < 1e-4 { return value - floor(value) < duty ? 1 : 0 }
        return clampUnit((inked(value + footprint / 2) - inked(value - footprint / 2)) / footprint)
    }

    /// Ink accumulated from 0 to `value` periods.
    private static func inked(_ value: Double) -> Double {
        let whole = floor(value), part = value - whole
        return whole * duty + (part < duty ? part : duty)
    }
}

/// f(z) shaded per pixel: hue from arg f, brightness bands from log₂|f|.
private struct PhasePortrait: Sendable {
    enum Function: CaseIterable {
        /// (z² − 1)(z − 2 − i)² / (z² + 2 + 2i): two simple zeros, a double one and two poles.
        case rational
        /// sin z / z: a row of zeros along the real axis, growing without bound off it.
        case sinc
        /// (z⁵ − 1) / (z² + 0.4 + 0.3i): the fifth roots of unity around two poles.
        case roots

        /// How much of the plane the screen's height covers.
        var span: Double {
            switch self {
            case .rational: 3.2
            case .sinc: 9
            case .roots: 2.4
            }
        }
    }

    static let ringSize = 512

    let function: Function
    /// Pixels per unit of z.
    let scale: Double
    let center: (x: Double, y: Double)
    /// The value of z at the middle of the screen.
    let offset: (x: Double, y: Double)
    /// `ringSize` RGB triples, 0–255, once around the palette.
    let ring: LaneBuffer<Double>
    let ground: PixelTone
    let isDark: Bool

    func shade(row: Int, columns: Int, into pixels: UnsafeMutablePointer<UInt8>) {
        let imaginary = (center.y - Double(row) - 0.5) / scale + offset.y
        var column = 0
        while column < columns {
            let real = (Double(column) + 0.5 - center.x) / scale + offset.x
            let value = evaluate(real, imaginary)
            let turn = atan2(value.im, value.re) / (2 * .pi) + 0.5
            let level = log2((value.re * value.re + value.im * value.im).squareRoot() + 1e-12)
            let band = level - floor(level)
            var shade = 0.72 + 0.28 * hermite(0, 0.92, band) - 0.28 * hermite(0.92, 1, band)
            let isochromatic = turn * 12 - floor(turn * 12)
            shade *= 1 - 0.08 * (1 - hermite(0, 0.06, isochromatic))
            let tone = ring.base + Int(turn * Double(Self.ringSize - 1)) * 3
            let amount = isDark ? shade : 0.35 + 0.65 * shade, pixel = pixels + column * 4
            pixel[0] = UInt8(ground.red + (tone[0] - ground.red) * amount + 0.5)
            pixel[1] = UInt8(ground.green + (tone[1] - ground.green) * amount + 0.5)
            pixel[2] = UInt8(ground.blue + (tone[2] - ground.blue) * amount + 0.5)
            pixel[3] = 255
            column += 1
        }
    }

    private func evaluate(_ real: Double, _ imaginary: Double) -> (re: Double, im: Double) {
        let square = (re: real * real - imaginary * imaginary, im: 2 * real * imaginary)
        switch function {
        case .rational:
            let shifted = (re: real - 2, im: imaginary - 1)
            let numerator = Self.times(
                (square.re - 1, square.im),
                Self.times(shifted, shifted)
            )
            return Self.over(numerator, (square.re + 2, square.im + 2))
        case .sinc:
            let sine = (re: sin(real) * cosh(imaginary), im: cos(real) * sinh(imaginary))
            return Self.over(sine, (real, imaginary))
        case .roots:
            let fifth = Self.times(Self.times(square, square), (real, imaginary))
            return Self.over((fifth.re - 1, fifth.im), (square.re + 0.4, square.im + 0.3))
        }
    }

    private static func times(
        _ lhs: (re: Double, im: Double), _ rhs: (re: Double, im: Double)
    ) -> (re: Double, im: Double) {
        (lhs.re * rhs.re - lhs.im * rhs.im, lhs.re * rhs.im + lhs.im * rhs.re)
    }

    private static func over(
        _ lhs: (re: Double, im: Double), _ rhs: (re: Double, im: Double)
    ) -> (re: Double, im: Double) {
        let norm = rhs.re * rhs.re + rhs.im * rhs.im
        let divisor = norm == 0 ? 1e-12 : norm
        return ((lhs.re * rhs.re + lhs.im * rhs.im) / divisor, (lhs.im * rhs.re - lhs.re * rhs.im) / divisor)
    }
}
