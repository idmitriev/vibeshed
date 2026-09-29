import CoreGraphics
import Foundation

/// QNX Photon's screen saver, the one that shipped on the QNX 6 demo CD: streams of digits
/// and katakana, drawn mirrored as Photon did, raining down in columns. Glyphs are 5×7
/// pixel bitmaps in 6×9 cells, at roughly the demo's 800×600 scale. On a dark desktop the
/// rain is the theme's green; on a light one (QNX Photon's periwinkle) it's white.
extension WallpaperCanvas {
    /// 5×7 glyphs, one byte per row from the top, the leftmost pixel in bit 4.
    static let rainGlyphs: [[UInt8]] = [
        [14, 17, 19, 21, 25, 17, 14], // 0
        [4, 12, 4, 4, 4, 4, 14], // 1
        [30, 1, 1, 14, 1, 1, 30], // 3
        [31, 16, 30, 1, 1, 17, 14], // 5
        [31, 1, 2, 4, 8, 8, 8], // 7
        [14, 17, 17, 14, 17, 17, 14], // 8
        [14, 17, 17, 15, 1, 2, 12], // 9
        [2, 4, 8, 16, 8, 4, 2], // <
        [8, 4, 2, 1, 2, 4, 8], // >
        [0, 0, 31, 0, 31, 0, 0], // =
        [0, 21, 14, 31, 14, 21, 0], // *
        [31, 1, 6, 4, 4, 8, 16], // ア
        [1, 2, 4, 12, 20, 4, 4], // イ
        [4, 31, 17, 1, 2, 4, 8], // ウ
        [8, 31, 9, 9, 17, 17, 18], // カ
        [8, 31, 4, 31, 4, 4, 4], // キ
        [8, 15, 18, 2, 2, 4, 8], // ケ
        [21, 21, 1, 2, 4, 8, 16], // ツ
        [0, 10, 10, 17, 17, 17, 0], // ハ
        [28, 3, 0, 28, 3, 0, 30], // ミ
        [30, 8, 31, 8, 8, 8, 7], // モ
        [14, 0, 31, 1, 1, 2, 12], // ラ
        [17, 17, 17, 17, 1, 2, 12], // リ
        [4, 31, 21, 21, 31, 4, 4], // 中
        [31, 17, 17, 31, 17, 17, 31], // 日
    ]

    mutating func paintRain() {
        let dot = max(1, (height / 420).rounded())
        let (cellWidth, cellHeight) = (6, 9)
        let columns = Int((width / dot).rounded(.up)), rows = Int((height / dot).rounded(.up))
        let cellColumns = columns / cellWidth + 1, cellRows = rows / cellHeight + 1
        let ground = palette["desktop"] ?? (isDark ? palette.darkerBackground : classicDesktop)
        let onDark = ground.relativeLuminance < 0.1
        let rain = onDark ? palette.green : ground.mix(.white, 0.9)
        // Trail tones, dimmest first, then the bright head.
        let steps = [0.2, 0.34, 0.48, 0.62, 0.78, 1]
        let tones = [Tone(ground)] + steps.map { Tone(ground.mix(rain, $0)) }
            + [Tone(onDark ? rain.mix(.white, 0.7) : .white)]

        // Per cell: its tone (0 = empty), glyph and whether it's mirrored.
        var level = [Int](repeating: 0, count: cellColumns * cellRows)
        var glyph = [Int](repeating: 0, count: cellColumns * cellRows)
        var mirrored = [Bool](repeating: false, count: cellColumns * cellRows)
        for index in glyph.indices {
            glyph[index] = rng.int(below: Self.rainGlyphs.count)
            mirrored[index] = rng.unit() < 0.5
        }
        for column in 0 ..< cellColumns where rng.unit() < 0.85 {
            for _ in 0 ..< 1 + (rng.unit() < 0.35 ? 1 : 0) {
                let head = rng.int(below: cellRows + 12) - 4
                let length = 5 + rng.int(below: max(1, cellRows * 2 / 3))
                let first = max(0, head - length + 1), last = min(head, cellRows - 1)
                guard first <= last else { continue }
                for row in first ... last {
                    let fade = 1 - Double(head - row) / Double(length)
                    let tone = row == head ? tones.count - 1 : 1 + min(Int(fade * Double(steps.count)), steps.count - 1)
                    level[row * cellColumns + column] = max(level[row * cellColumns + column], tone)
                }
            }
        }

        paintPixels(dot: dot) { column, row in
            let cell = (row / cellHeight) * cellColumns + column / cellWidth
            let x = column % cellWidth, y = row % cellHeight - 1
            guard level[cell] > 0, x < 5, y >= 0, y < 7 else { return tones[0] }
            let bit = mirrored[cell] ? x : 4 - x
            return Self.rainGlyphs[glyph[cell]][y] >> UInt8(bit) & 1 == 1 ? tones[level[cell]] : tones[0]
        }
    }
}
