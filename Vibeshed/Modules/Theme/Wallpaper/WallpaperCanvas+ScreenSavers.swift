import CoreGraphics
import Foundation

/// Stills of classic screen savers that doubled as desktop backgrounds, following the
/// originals' drawing code with the palette's colors.
extension WallpaperCanvas {
    // MARK: - Leaves (Haiku)

    /// Haiku's Leaves screen saver (Deyan Genovski, Geoffry Song; MIT): leaves at random
    /// sizes, angles and flips, each filled with a two-tone gradient and a soft dark edge,
    /// piling up on the desktop. Haiku's orange/green/gold pairs come from the palette.
    mutating func paintLeaves() {
        fill(palette["desktop"] ?? base)
        let pairs = [
            (palette.orange, palette.yellow),
            (palette.green, palette["bright_green"] ?? palette.green.lightened(0.3)),
            (palette.yellow, palette.yellow.lightened(0.45)),
        ]
        // Haiku: 150 / 372 / 2000 of the screen width per leaf unit, plus up to 50% variation.
        let baseScale = width * 150 / HaikuLeaf.width / 2000
        // Leaf size scales with the width, so a fixed count gives the same coverage (~30%)
        // at any resolution.
        for _ in 0 ..< 110 {
            let scale = baseScale * (1 + rng.unit() * 0.5)
            var transform = CGAffineTransform(translationX: -HaikuLeaf.width / 2, y: -HaikuLeaf.height / 2)
                .concatenating(CGAffineTransform(rotationAngle: rng.between(0, .pi * 2)))
            if rng.unit() < 0.5 { transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1)) }
            transform = transform
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: width * rng.unit(), y: height * rng.unit()))
            let pair = pairs[Int(rng.between(0, Double(pairs.count)))]
            drawLeaf(HaikuLeaf.path(transform), center: CGPoint(x: HaikuLeaf.width / 2, y: HaikuLeaf.height / 2)
                .applying(transform), scale: scale, colors: pair)
        }
    }

    private func drawLeaf(_ path: CGPath, center: CGPoint, scale: CGFloat, colors: (ThemeColor, ThemeColor)) {
        // Haiku strokes the outline three times in 20%-black at pens 4, 2 and hairline, each
        // nudged down a little — a soft shadowed edge.
        let shadow = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 50 / 255)
        for step in stride(from: 2, through: 0, by: -1) {
            context.saveGState()
            context.translateBy(x: CGFloat(step) * 0.1 * unit, y: -CGFloat(step) * 0.3 * unit)
            context.addPath(path)
            context.setStrokeColor(shadow)
            context.setLineWidth(max(CGFloat(step) * 2 * unit * 0.9, unit * 0.6))
            context.setLineJoin(.round)
            context.strokePath()
            context.restoreGState()
        }
        let offset = CGPoint(x: 60 * scale, y: 80 * scale)
        guard let gradient = CGGradient(
            colorsSpace: space, colors: [colors.0.cgColor, colors.1.cgColor] as CFArray, locations: [0, 1]
        ) else { return }
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: center.x - offset.x, y: center.y - offset.y),
            end: CGPoint(x: center.x + offset.x, y: center.y + offset.y),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    // MARK: - Polyhedra (NeXTSTEP BackSpace)

    /// NeXTSTEP BackSpace's Polyhedra module (Simon Marchant & Paul Brown, 1991), which
    /// BackSpace could run as the live workspace background: a regular solid in perspective
    /// on black, drawn back to front — some faces filled from its five-color table (red,
    /// green, blue, gold, orange; here the palette's bright terminal colors), the rest
    /// see-through — with every edge stroked white.
    mutating func paintPolyhedra() {
        fill(isDark ? palette.darkerBackground : palette.foreground.mix(.black, 0.6))
        let solid = RegularSolid.all[Int(rng.between(0, Double(RegularSolid.all.count)))]
        let turn = { (rng: inout SeededGenerator) in rng.between(0, .pi * 2) }
        let rotation = Rotation3(yaw: turn(&rng), pitch: turn(&rng), roll: turn(&rng))
        let vertices = solid.vertices.map(rotation.apply)

        let radius = Double(height) * 0.34
        let center = point(rng.between(0.3, 0.7), rng.between(0.35, 0.65))
        let camera = 3.2
        let screen = vertices.map { vertex in
            let perspective = camera / (camera + vertex.z)
            return CGPoint(x: center.x + vertex.x * radius * perspective, y: center.y + vertex.y * radius * perspective)
        }

        // Like the original's per-solid tables: about a third of the faces filled (at least
        // one), each with the next color of the table; the rest see-through.
        let lookup = [palette.ansi[9], palette.ansi[10], palette.ansi[12], palette.ansi[11], palette.orange]
        var candidates = Array(solid.faces.indices)
        var fills: [Int: ThemeColor] = [:]
        for slot in 0 ..< max(1, solid.faces.count / 3) {
            let face = candidates.remove(at: Int(rng.between(0, Double(candidates.count))))
            fills[face] = lookup[slot % lookup.count]
        }
        let order = solid.faces.indices.sorted { lhs, rhs in
            averageDepth(solid.faces[lhs], vertices) > averageDepth(solid.faces[rhs], vertices)
        }
        let edge = [palette.background, palette.brightForeground].max { $0.relativeLuminance < $1.relativeLuminance }
            ?? .white
        context.setLineJoin(.round)
        context.setLineWidth(max(1, unit * 1.6))
        for face in order {
            context.addLines(between: solid.faces[face].map { screen[$0] })
            context.closePath()
            if let fillColor = fills[face] {
                context.setFillColor(fillColor.cgColor)
                context.setStrokeColor(edge.cgColor)
                context.drawPath(using: .fillStroke)
            } else {
                context.setStrokeColor(edge.cgColor)
                context.strokePath()
            }
        }
    }

    private func averageDepth(_ face: [Int], _ vertices: [SIMD3<Double>]) -> Double {
        face.map { vertices[$0].z }.reduce(0, +) / Double(face.count)
    }
}

// MARK: - Haiku's leaf

/// The leaf outline from Haiku's Leaves screen saver: a start point and 18 cubic Béziers.
private enum HaikuLeaf {
    static let width: CGFloat = 372
    static let height: CGFloat = 121
    static let start = CGPoint(x: 56.24793, y: 15.46287)
    static let curves: [(CGPoint, CGPoint, CGPoint)] = [
        (.init(x: 61.14, y: 28.89), .init(x: 69.78, y: 38.25), .init(x: 83.48, y: 44.17)),
        (.init(x: 99.46, y: 37.52), .init(x: 113.27, y: 29.61), .init(x: 134.91, y: 30.86)),
        (.init(x: 130.58, y: 36.53), .init(x: 126.74, y: 42.44), .init(x: 123.84, y: 48.81)),
        (.init(x: 131.81, y: 42.22), .init(x: 137.53, y: 38.33), .init(x: 144.37, y: 33.10)),
        (.init(x: 169.17, y: 23.55), .init(x: 198.90, y: 15.55), .init(x: 232.05, y: 10.51)),
        (.init(x: 225.49, y: 18.37), .init(x: 219.31, y: 28.17), .init(x: 217.41, y: 40.24)),
        (.init(x: 227.70, y: 26.60), .init(x: 239.97, y: 14.63), .init(x: 251.43, y: 8.36)),
        (.init(x: 288.89, y: 9.12), .init(x: 322.73, y: 14.33), .init(x: 346.69, y: 31.67)),
        (.init(x: 330.49, y: 37.85), .init(x: 314.36, y: 44.25), .init(x: 299.55, y: 54.17)),
        (.init(x: 292.48, y: 52.54), .init(x: 289.31, y: 49.70), .init(x: 285.62, y: 47.03)),
        (.init(x: 283.73, y: 54.61), .init(x: 284.46, y: 57.94), .init(x: 285.62, y: 60.60)),
        (.init(x: 259.78, y: 76.14), .init(x: 233.24, y: 90.54), .init(x: 202.41, y: 98.10)),
        (.init(x: 194.43, y: 95.36), .init(x: 185.96, y: 92.39), .init(x: 179.63, y: 88.33)),
        (.init(x: 180.15, y: 94.75), .init(x: 182.73, y: 99.76), .init(x: 185.62, y: 104.53)),
        (.init(x: 154.83, y: 119.46), .init(x: 133.21, y: 118.97), .init(x: 125.62, y: 94.88)),
        (.init(x: 124.70, y: 98.79), .init(x: 124.11, y: 103.67), .init(x: 124.19, y: 110.60)),
        (.init(x: 116.42, y: 111.81), .init(x: 85.82, y: 99.60), .init(x: 83.25, y: 51.96)),
        (.init(x: 62.50, y: 42.57), .init(x: 58.12, y: 33.18), .init(x: 50.98, y: 23.81)),
    ]

    static func path(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start, transform: transform)
        for (control1, control2, end) in curves {
            path.addCurve(to: end, control1: control1, control2: control2, transform: transform)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Regular solids

/// The five Platonic solids, unit circumradius. Faces are derived from each solid's dual:
/// every dual vertex is a face normal, and the face is the set of vertices furthest along it.
struct RegularSolid {
    let vertices: [SIMD3<Double>]
    let faces: [[Int]]

    static let all: [RegularSolid] = {
        let phi = (1 + sqrt(5.0)) / 2
        let cube = signs3().map { SIMD3($0.x, $0.y, $0.z) }
        let octahedron = [SIMD3<Double>(1, 0, 0), [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
        let tetrahedron = [SIMD3<Double>(1, 1, 1), [1, -1, -1], [-1, 1, -1], [-1, -1, 1]]
        let icosahedron = cyclic(0, 1, phi)
        // Oriented as the icosahedron's dual (its vertices sit over the icosahedron's faces).
        let dodecahedron = cube + cyclic(0, phi, 1 / phi)
        return [
            RegularSolid(tetrahedron, normals: tetrahedron.map { -$0 }),
            RegularSolid(cube, normals: octahedron),
            RegularSolid(octahedron, normals: cube),
            RegularSolid(dodecahedron, normals: icosahedron),
            RegularSolid(icosahedron, normals: dodecahedron),
        ]
    }()

    private init(_ vertices: [SIMD3<Double>], normals: [SIMD3<Double>]) {
        let radius = (vertices[0] * vertices[0]).sum().squareRoot()
        let unitVertices = vertices.map { $0 / radius }
        self.vertices = unitVertices
        faces = normals.map { normal in
            let dots = unitVertices.map { ($0 * normal).sum() }
            let furthest = dots.max() ?? 0
            let members = unitVertices.indices.filter { dots[$0] > furthest - 1e-6 }
            return Self.ordered(members, around: normal, in: unitVertices)
        }
    }

    /// Face vertices sorted by angle around the face normal, so they form a polygon.
    private static func ordered(_ members: [Int], around normal: SIMD3<Double>, in vertices: [SIMD3<Double>]) -> [Int] {
        let centroid = members.map { vertices[$0] }.reduce(.zero, +) / Double(members.count)
        let axis = normal / (normal * normal).sum().squareRoot()
        let first = vertices[members[0]] - centroid
        let across = first / (first * first).sum().squareRoot()
        let up = SIMD3(
            axis.y * across.z - axis.z * across.y,
            axis.z * across.x - axis.x * across.z,
            axis.x * across.y - axis.y * across.x
        )
        let angle = { (vertex: Int) -> Double in
            let offset = vertices[vertex] - centroid
            return atan2((offset * up).sum(), (offset * across).sum())
        }
        return members.sorted { angle($0) < angle($1) }
    }

    /// (±1, ±1, ±1).
    private static func signs3() -> [SIMD3<Double>] {
        [-1.0, 1].flatMap { xs in [-1.0, 1].flatMap { ys in [-1.0, 1].map { zs in SIMD3(xs, ys, zs) } } }
    }

    /// Cyclic permutations of (±a, ±b, ±c): (a,b,c), (b,c,a), (c,a,b) with every sign.
    private static func cyclic(_ first: Double, _ second: Double, _ third: Double) -> [SIMD3<Double>] {
        var points: [SIMD3<Double>] = []
        for secondSign in [-1.0, 1] {
            for thirdSign in [-1.0, 1] {
                let base = SIMD3(first, second * secondSign, third * thirdSign)
                points += [base, SIMD3(base.y, base.z, base.x), SIMD3(base.z, base.x, base.y)]
            }
        }
        return first == 0 ? points : points + points.map { SIMD3(-$0.x, $0.y, $0.z) }
    }
}

private struct Rotation3 {
    let yaw: Double
    let pitch: Double
    let roll: Double

    func apply(_ point: SIMD3<Double>) -> SIMD3<Double> {
        let (cy, sy, cp, sp, cr, sr) = (cos(yaw), sin(yaw), cos(pitch), sin(pitch), cos(roll), sin(roll))
        let x1 = point.x * cy - point.z * sy, z1 = point.x * sy + point.z * cy
        let y2 = point.y * cp - z1 * sp, z2 = point.y * sp + z1 * cp
        return SIMD3(x1 * cr - y2 * sr, x1 * sr + y2 * cr, z2)
    }
}
