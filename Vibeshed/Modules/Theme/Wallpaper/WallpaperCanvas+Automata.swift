import CoreGraphics
import Foundation

/// Cellular automata in crisp cells: panels of Wolfram's elementary automata, and
/// Griffeath's cyclic automaton grown from noise into spirals. Each grid is painted as one
/// small bitmap and scaled up without smoothing.
///
/// Automata is adapted from gart (https://github.com/igr/gart), © 2022 Igor Spasić, BSD 2-Clause License.
extension WallpaperCanvas {
    // MARK: - Automata

    /// Rules worth looking at, with the cells they read on each side: twelve of the 256
    /// three-cell rules and six five-cell ones.
    private static let automatonRules: [(rule: Int, reach: Int)] = [
        (30, 1), (45, 1), (73, 1), (86, 1), (89, 1), (105, 1), (110, 1), (124, 1), (135, 1), (150, 1), (54, 1),
        (57, 1), (838, 2), (209_218, 2), (774_857, 2), (37_788_005, 2), (22_047_073, 2), (1_069_090_987, 2),
    ]

    /// A Mondrian-like layout of panels (after gart's Rule), each running its own elementary
    /// cellular automaton in two tones, time flowing down. Three passes split every panel
    /// that's big enough into four, at random multiples of a gap; each panel then starts its
    /// rule from a random row and skips the first forty generations, so it opens on its
    /// settled texture rather than the noise. Drawn in unit space.
    mutating func paintAutomata() {
        enterUnitSpace()
        let gap = 1000.0 / 10.24
        var panels = [CGRect(x: 0, y: 0, width: unitWidth, height: unitHeight)]
        for _ in 0 ..< 3 {
            panels = panels.flatMap { divide($0, gap: gap) }
        }
        fill(isDark ? base.darkened(0.3) : palette.background)
        let hues = harmony(5, keepingTwin: true)
        context.interpolationQuality = .none
        for panel in panels {
            paintAutomatonPanel(panel, hues: hues)
        }
    }

    /// `panel` split into four at random multiples of `gap`, if it's at least four gaps
    /// wide and tall.
    private mutating func divide(_ panel: CGRect, gap: Double) -> [CGRect] {
        guard panel.width >= gap * 4, panel.height >= gap * 4 else { return [panel] }
        let across = Double(1 + rng.int(below: Int(panel.width / gap) - 1)) * gap
        let down = Double(1 + rng.int(below: Int(panel.height / gap) - 1)) * gap
        let (left, top) = (panel.minX, panel.minY)
        return [
            CGRect(x: left, y: top, width: across, height: down),
            CGRect(x: left + across, y: top, width: panel.width - across, height: down),
            CGRect(x: left, y: top + down, width: across, height: panel.height - down),
            CGRect(x: left + across, y: top + down, width: panel.width - across, height: panel.height - down),
        ]
    }

    private mutating func paintAutomatonPanel(_ panel: CGRect, hues: [ThemeColor]) {
        let cell = 4.0
        let (rule, reach) = rng.pick(Self.automatonRules)
        let columns = Int((panel.width / cell).rounded(.up)), generations = Int((panel.height / cell).rounded(.up))
        let first = (0 ..< columns).map { _ in rng.unit() < 0.5 }
        let history = ElementaryAutomaton(rule: rule, reach: reach).run(from: first, generations: generations + 40)
        let on = rng.pick(hues), off = rng.pick(hues)
        let ink = isDark ? on : on.darkened(0.1)
        let paper = isDark ? muted(off, 0.78) : palette.background.mix(off, 0.15)
        let (paperPixel, inkPixel) = (Self.packed(paper), Self.packed(ink))
        let pixels = Self.pixels(count: columns * generations) { cell in
            history[40 + cell / columns][cell % columns] ? inkPixel : paperPixel
        }
        guard let image = bitmapImage(columns: columns, rows: generations, pixels: pixels) else { return }
        context.saveGState()
        // The gutters between panels are the frame showing through.
        context.clip(to: panel.insetBy(dx: 3.5, dy: 3.5))
        drawUpright(image, in: CGRect(
            x: panel.minX, y: panel.minY, width: Double(columns) * cell, height: Double(generations) * cell
        ))
        context.restoreGState()
    }

    // MARK: - Cyclic

    /// Griffeath's cyclic cellular automaton (Fisch, Gravner & Griffeath, "Threshold-range
    /// scaling of excitable cellular automata", 1991): fourteen states in a ring, and a cell
    /// moves on to the next state as soon as a neighbor holds it. From random noise, waves
    /// start chasing each other around and spirals take over the screen: square Greek-key
    /// spirals with the four nearest neighbors (two times in three), rounder ones with all
    /// eight. Drawn in 4-unit cells.
    mutating func paintCyclic() {
        let moore = rng.int(below: 3) == 2
        // Whole words of eight cells; the extra columns run off the right edge.
        let columns = (Int((unitWidth / 4).rounded(.up)) + 7) / 8 * 8, rows = 250
        let automaton = CyclicAutomaton(columns: columns, rows: rows)
        defer { automaton.deallocate() }
        automaton.scatter(using: &rng)
        automaton.run(steps: moore ? 900 : 420, moore: moore)
        let pixels = cyclicTones().withUnsafeBufferPointer { tones in
            Self.pixels(count: columns * rows) { tones[Int(automaton.cells[$0])] }
        }
        guard let image = bitmapImage(columns: columns, rows: rows, pixels: pixels) else { return fill(base) }
        let size = CGSize(width: CGFloat(columns) * 4 * unit, height: CGFloat(rows) * 4 * unit)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(origin: CGPoint(x: 0, y: height - size.height), size: size))
    }

    /// A ring of four tones crossfaded smoothly over the fourteen states, so each wave reads
    /// as a band of color rather than fourteen steps.
    private func cyclicTones() -> [UInt32] {
        let hues = harmony(4, keepingTwin: true)
        let ring = isDark
            ? [hues[0], muted(hues.cycling(1), 0.25), base.mix(hues[0], 0.12), muted(hues.cycling(2), 0.3)]
            : [
                hues[0].mix(palette.background, 0.15), hues.cycling(1).mix(palette.background, 0.45),
                palette.background, hues.cycling(2).mix(palette.background, 0.4),
            ]
        return (0 ..< CyclicAutomaton.states).map { state in
            let position = Double(state) / Double(CyclicAutomaton.states) * Double(ring.count)
            let index = Int(position)
            let tone = ring[index].mix(ring.cycling(index + 1), smoothstep(0, 1, position - Double(index)))
            return Self.packed(tone)
        }
    }

    /// A color as one RGBX pixel's bytes, read as a (little-endian) word.
    static func packed(_ color: ThemeColor) -> UInt32 {
        UInt32(color.red8) | UInt32(color.green8) << 8 | UInt32(color.blue8) << 16 | 0xFF00_0000
    }

    /// RGBX pixels for `count` cells, each the packed tone `tone` gives it.
    static func pixels(count: Int, tone: (Int) -> UInt32) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: count * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let words = bytes.bindMemory(to: UInt32.self)
            var cell = 0
            while cell < count {
                words[cell] = tone(cell)
                cell += 1
            }
        }
        return pixels
    }
}

/// A one-dimensional, two-state cellular automaton on a ring of cells, in Wolfram's
/// numbering: a cell's next state is bit v of `rule`, where v reads its neighborhood
/// (`reach` cells on each side) as a binary number, the leftmost cell most significant.
struct ElementaryAutomaton {
    let rule: Int
    let reach: Int

    /// `generations` rows, the first being `first`. The ends of each row wrap around.
    func run(from first: [Bool], generations: Int) -> [[Bool]] {
        let lookup = (0 ..< 1 << (2 * reach + 1)).map { (rule >> $0) & 1 == 1 }
        let count = first.count
        var row = first, history: [[Bool]] = []
        for _ in 0 ..< generations {
            history.append(row)
            row = (0 ..< count).map { column in
                var neighborhood = 0
                for offset in -reach ... reach {
                    neighborhood = neighborhood * 2 + (row[((column + offset) % count + count) % count] ? 1 : 0)
                }
                return lookup[neighborhood]
            }
        }
        return history
    }
}

/// Griffeath's cyclic automaton on a grid that wraps at every edge, with threshold one.
/// Cells are bytes packed eight to a 64-bit word, and a step updates a whole word at once
/// with plain integer arithmetic (SWAR). Rows are split across the render lanes; each
/// step reads one buffer and writes the other, so the lanes never race.
private final class CyclicAutomaton {
    static let states: UInt64 = 14

    let columns: Int
    let rows: Int
    private let words: Int
    private var front: LaneBuffer<UInt64>
    private var back: LaneBuffer<UInt64>

    /// `columns` must be a multiple of eight.
    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        words = columns / 8
        front = LaneBuffer(zeroed: words * rows)
        back = LaneBuffer(zeroed: words * rows)
    }

    func deallocate() {
        front.deallocate()
        back.deallocate()
    }

    /// Every cell's state, row-major (byte order is little-endian on every Mac).
    var cells: UnsafePointer<UInt8> {
        UnsafePointer(UnsafeMutableRawPointer(front.base).assumingMemoryBound(to: UInt8.self))
    }

    /// Random states everywhere, four cells from each draw.
    func scatter(using rng: inout SeededGenerator) {
        let bytes = UnsafeMutableRawPointer(front.base).assumingMemoryBound(to: UInt8.self)
        var cell = 0
        while cell < columns * rows {
            let draw = rng.next()
            for chunk in 0 ..< min(4, columns * rows - cell) {
                let uniform = (draw &>> (16 * UInt64(chunk))) & 0xFFFF
                bytes[cell + chunk] = UInt8((uniform * Self.states) &>> 16)
            }
            cell += 4
        }
    }

    func run(steps: Int, moore: Bool) {
        for _ in 0 ..< steps {
            let (source, target, words, rows) = (front, back, words, rows)
            RenderLanes.split(rows) { _, band in
                for row in band {
                    Self.advance(row: row, from: source, to: target, shape: (words, rows), moore: moore)
                }
            }
            (front, back) = (back, front)
        }
    }

    /// One row's next generation: every byte becomes its successor state where a neighbor
    /// already holds that state.
    private static func advance(
        row: Int, from source: LaneBuffer<UInt64>, to target: LaneBuffer<UInt64>, shape: (words: Int, rows: Int),
        moore: Bool
    ) {
        let words = shape.words
        let middle = source.base + row * words, output = target.base + row * words
        let above = source.base + (row + shape.rows - 1) % shape.rows * words
        let below = source.base + (row + 1) % shape.rows * words
        var previous = middle[words - 1], current = middle[0], word = 0
        while word < words {
            let left = word == 0 ? words - 1 : word - 1, right = word + 1 == words ? 0 : word + 1
            let next = middle[right]
            let want = successor(current)
            var hit = zeroBytes(shiftedRight(current, previous) ^ want) | zeroBytes(shiftedLeft(current, next) ^ want)
            hit |= zeroBytes(above[word] ^ want) | zeroBytes(below[word] ^ want)
            if moore {
                hit |= zeroBytes(shiftedRight(above[word], above[left]) ^ want)
                    | zeroBytes(shiftedLeft(above[word], above[right]) ^ want)
                    | zeroBytes(shiftedRight(below[word], below[left]) ^ want)
                    | zeroBytes(shiftedLeft(below[word], below[right]) ^ want)
            }
            output[word] = current ^ ((current ^ want) & ((hit &>> 7) &* 0xFF))
            (previous, current, word) = (current, next, word + 1)
        }
    }

    /// Each cell's left neighbor in its place: the word moved one byte up, with the last
    /// byte of the word before carried in.
    private static func shiftedRight(_ word: UInt64, _ before: UInt64) -> UInt64 {
        (word &<< 8) | (before &>> 56)
    }

    /// Each cell's right neighbor in its place.
    private static func shiftedLeft(_ word: UInt64, _ after: UInt64) -> UInt64 {
        (word &>> 8) | (after &<< 56)
    }

    /// Every byte's next state, wrapping 13 to 0.
    private static func successor(_ word: UInt64) -> UInt64 {
        let next = word &+ 0x0101_0101_0101_0101
        let wrapped = zeroBytes(next ^ (0x0101_0101_0101_0101 &* states))
        return next & ~((wrapped &>> 7) &* 0xFF)
    }

    /// 0x80 in every byte of `word` that's zero, 0 in the others (exact: no borrow
    /// crosses between bytes).
    private static func zeroBytes(_ word: UInt64) -> UInt64 {
        let low: UInt64 = 0x7F7F_7F7F_7F7F_7F7F
        return ~(((word & low) &+ low) | word | low)
    }
}
