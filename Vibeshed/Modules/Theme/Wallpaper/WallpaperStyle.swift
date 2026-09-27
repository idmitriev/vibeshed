import Foundation

/// Procedural wallpaper algorithms, each painting purely from a theme palette.
enum WallpaperStyle: String, CaseIterable, Sendable {
    case glow, mesh, waves, ridges, bokeh, lowpoly, topographic, sunset, arcs, halftone
    case pulsar, guilloche, sashiko, attractor
    case bauhaus, destijl, truchet, terrazzo, circles, isometric, penrose
    case leaves, warp, textmode, polyhedra, maze, dither, pipes
    case solid

    /// Config value that picks a style per theme (stable, so each theme keeps its look).
    static let automatic = "auto"

    /// What `auto` chooses from.
    static let varied: [WallpaperStyle] = allCases.filter { $0 != .solid }

    var displayName: String {
        switch self {
        case .glow: "Glow"
        case .mesh: "Mesh Gradient"
        case .waves: "Waves"
        case .ridges: "Ridges"
        case .bokeh: "Bokeh"
        case .lowpoly: "Low Poly"
        case .topographic: "Topographic"
        case .sunset: "Retro Sunset"
        case .arcs: "Retro Arcs"
        case .halftone: "Halftone"
        case .pulsar: "Pulsar"
        case .guilloche: "Guilloché"
        case .sashiko: "Sashiko"
        case .attractor: "Attractor"
        case .bauhaus: "Bauhaus"
        case .destijl: "De Stijl"
        case .truchet: "Truchet"
        case .terrazzo: "Terrazzo"
        case .circles: "Circle Packing"
        case .isometric: "Isometric Terraces"
        case .penrose: "Penrose"
        case .leaves: "Leaves"
        case .warp: "Warp Speed"
        case .textmode: "Text Mode"
        case .polyhedra: "Polyhedra"
        case .maze: "10 PRINT"
        case .dither: "Dither"
        case .pipes: "Pipes"
        case .solid: "Solid"
        }
    }

    var summary: String {
        switch self {
        case .glow: "Diagonal wash lit by soft accent glows"
        case .mesh: "Smooth blend of the palette's key colors"
        case .waves: "Layered sine waves rising from the bottom"
        case .ridges: "Mountain ridges fading into a sky, with a sun"
        case .bokeh: "Out-of-focus light discs in palette hues"
        case .lowpoly: "Faceted triangles over a color field"
        case .topographic: "Contour lines of a noise landscape"
        case .sunset: "Striped sun over a perspective grid"
        case .arcs: "Seventies rainbow bands from a corner"
        case .halftone: "Dot grid swelling toward the accent"
        case .pulsar: "Stacked line plots peaking in the middle, after the Unknown Pleasures cover"
        case .guilloche: "Hairline rosettes braided from sine-modulated rings, like a banknote"
        case .sashiko: "Hitomezashi running stitches, with the shapes they close off tinted"
        case .attractor: "A Clifford strange attractor, shaded by how often each spot is visited"
        case .bauhaus: "Tiles of quarter circles, half circles, triangles, lenses and stripes"
        case .destijl: "Mondrian's rectangles: heavy rules and a few red, blue and yellow panels"
        case .truchet: "Quarter-circle tiles in random turns, two-colored so regions alternate"
        case .terrazzo: "Stone chips of every size scattered over a mottled ground"
        case .circles: "Circles grown until they touch: solid, ringed and outlined"
        case .isometric: "Isometric blocks stacked to a noise heightmap, shaded on three faces"
        case .penrose: "Penrose's thin and thick rhombs, a tiling that never repeats"
        case .leaves: "Haiku's Leaves screen saver: gradient leaves piling up on the desktop"
        case .warp: "Star streaks at warp speed, after OS/2 Warp"
        case .textmode: "A text-mode screen: shaded desktop, menus and boxed dialogs"
        case .polyhedra: "NeXTSTEP BackSpace's Polyhedra: a regular solid in perspective on black"
        case .maze: "The Commodore 64's one-line maze, its sealed-off rooms tinted"
        case .dither: "A banded planet in four tones, Bayer-dithered into chunky pixels"
        case .pipes: "Shiny pipes wandering a 3D grid, after the Windows NT screen saver"
        case .solid: "Just the background color"
        }
    }

    var icon: String {
        switch self {
        case .glow: "light.max"
        case .mesh: "circle.hexagongrid"
        case .waves: "water.waves"
        case .ridges: "mountain.2"
        case .bokeh: "circle.circle"
        case .lowpoly: "triangle"
        case .topographic: "map"
        case .sunset: "sunset"
        case .arcs: "rainbow"
        case .halftone: "circle.grid.3x3"
        case .pulsar: "waveform.path.ecg"
        case .guilloche: "seal"
        case .sashiko: "square.dashed"
        case .attractor: "hurricane"
        case .bauhaus: "square.on.circle"
        case .destijl: "square.split.bottomrightquarter"
        case .truchet: "point.topleft.down.curvedto.point.bottomright.up"
        case .terrazzo: "aqi.medium"
        case .circles: "circles.hexagonpath"
        case .isometric: "square.stack.3d.up"
        case .penrose: "rhombus"
        case .leaves: "leaf"
        case .warp: "sparkles"
        case .textmode: "terminal"
        case .polyhedra: "cube.transparent"
        case .maze: "chevron.left.forwardslash.chevron.right"
        case .dither: "checkerboard.rectangle"
        case .pipes: "pipe.and.drop"
        case .solid: "square.fill"
        }
    }

    /// A style name from config (`auto` resolves per theme). Nil if unknown.
    static func resolve(_ name: String, slug: String) -> WallpaperStyle? {
        if name.lowercased() == automatic {
            return varied[Int(StableHash.of(slug) % UInt64(varied.count))]
        }
        return WallpaperStyle(rawValue: name.lowercased())
    }
}

/// Everything that determines a generated wallpaper besides the palette.
struct WallpaperChoice: Sendable, Equatable {
    let style: WallpaperStyle
    /// Variation within the style (positions, shapes). Same seed, same picture.
    let seed: UInt64
    /// Fine film grain texture on top.
    let grain: Bool
}

// MARK: - Deterministic randomness

enum StableHash {
    /// FNV-1a — stable across launches, unlike `Hasher`.
    static func of(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return hash
    }
}

/// SplitMix64: tiny, fast, and reproducible from a seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func unit() -> Double {
        Double.random(in: 0 ..< 1, using: &self)
    }

    mutating func between(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * unit()
    }

    /// An integer in `0 ..< count`.
    mutating func int(below count: Int) -> Int {
        min(Int(unit() * Double(count)), count - 1)
    }

    mutating func pick<Element>(_ elements: [Element]) -> Element {
        elements[int(below: elements.count)]
    }
}

/// Smooth 2D value noise with fractal octaves, in `0...1`.
struct ValueNoise: Sendable {
    let seed: UInt64

    func value(_ x: Double, _ y: Double) -> Double {
        let x0 = floor(x)
        let y0 = floor(y)
        let fx = smooth(x - x0)
        let fy = smooth(y - y0)
        let ix = Int64(x0)
        let iy = Int64(y0)
        let top = lattice(ix, iy) + (lattice(ix + 1, iy) - lattice(ix, iy)) * fx
        let bottom = lattice(ix, iy + 1) + (lattice(ix + 1, iy + 1) - lattice(ix, iy + 1)) * fx
        return top + (bottom - top) * fy
    }

    func fractal(_ x: Double, _ y: Double, octaves: Int = 4) -> Double {
        var total = 0.0
        var amplitude = 0.5
        var frequency = 1.0
        var norm = 0.0
        for _ in 0 ..< octaves {
            total += value(x * frequency, y * frequency) * amplitude
            norm += amplitude
            amplitude *= 0.5
            frequency *= 2.03
        }
        return total / norm
    }

    private func smooth(_ value: Double) -> Double {
        value * value * value * (value * (value * 6 - 15) + 10)
    }

    private func lattice(_ x: Int64, _ y: Int64) -> Double {
        var generator = SeededGenerator(
            seed: seed ^ (UInt64(bitPattern: x) &* 0x9E37_79B9) ^ (UInt64(bitPattern: y) &* 0x85EB_CA77_C2B2_AE63)
        )
        return generator.unit()
    }
}
