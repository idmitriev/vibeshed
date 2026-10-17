import Foundation

// MARK: - Searchable text

extension FuzzyMatcher {
    /// A title or subtitle prepared once per action (when the corpus is built), so
    /// per-keystroke matching compares integers and does no string work.
    struct SearchText: Sendable {
        let original: String
        /// One code per Character, case-folded (see `code(of:)`).
        let codes: [UInt32]
        /// Whether each Character starts a word: the first one, one after a space or
        /// punctuation ("Maximize/Restore", "Siri & Spotlight", "Wi-Fi"), or a capital
        /// after a lowercase letter ("GitHub").
        let wordStarts: [Bool]

        init(_ original: String) {
            self.original = original
            var codes: [UInt32] = []
            var wordStarts: [Bool] = []
            codes.reserveCapacity(original.utf8.count)
            wordStarts.reserveCapacity(original.utf8.count)
            var previous: CharacterClass?
            for character in original {
                let current = CharacterClass(character)
                codes.append(FuzzyMatcher.code(of: character))
                wordStarts.append(previous.map { current.startsWord(after: $0) } ?? true)
                previous = current
            }
            self.codes = codes
            self.wordStarts = wordStarts
        }
    }

    /// A typed query, lowercased and coded once per keystroke.
    struct Query: Sendable {
        let lowered: String
        let codes: [UInt32]

        init(_ text: String) {
            lowered = text.lowercased()
            codes = text.map(FuzzyMatcher.code(of:))
        }

        var isEmpty: Bool {
            codes.isEmpty
        }
    }

    /// A Character's case-folded code: an ASCII one is its lowercase byte; any other is
    /// a hash of its lowercased form with the top bit set, so it can't collide with
    /// ASCII. String hashing honors canonical equivalence, so "é" precomposed (typed)
    /// and decomposed (a file-system app name) agree. Hashes are per process, as are
    /// the codes.
    static func code(of character: Character) -> UInt32 {
        if let ascii = character.asciiValue {
            return UInt32(ascii >= 65 && ascii <= 90 ? ascii + 32 : ascii)
        }
        return 0x8000_0000 | UInt32(truncatingIfNeeded: String(character).lowercased().hashValue) & 0x7FFF_FFFF
    }
}

/// What word boundaries need to know about a Character.
private struct CharacterClass {
    let isWordCharacter: Bool
    let isApostrophe: Bool
    let isLowercase: Bool
    let isUppercase: Bool

    init(_ character: Character) {
        if let ascii = character.asciiValue {
            isUppercase = ascii >= 65 && ascii <= 90
            isLowercase = ascii >= 97 && ascii <= 122
            isWordCharacter = isUppercase || isLowercase || (ascii >= 48 && ascii <= 57)
            isApostrophe = ascii == 39
        } else {
            isUppercase = character.isUppercase
            isLowercase = character.isLowercase
            isWordCharacter = character.isLetter || character.isNumber
            isApostrophe = character == "\u{2019}"
        }
    }

    /// A word starts after a space or punctuation (but not an apostrophe: "Display's"),
    /// or at a capital after a lowercase letter.
    func startsWord(after previous: CharacterClass) -> Bool {
        guard isWordCharacter else { return false }
        if !previous.isWordCharacter, !previous.isApostrophe { return true }
        return previous.isLowercase && isUppercase
    }
}

// MARK: - Alignment

extension FuzzyMatcher {
    /// How each run of consecutive matched characters (a chunk) counts, per character,
    /// by where it starts. Ordered as `Alignment` indexes them.
    enum Chunk {
        /// At the very start: the user is typing the name.
        static let textStart = 1.5
        /// At a word start: a word of the name, or its initials ("pr" in Pull Requests).
        static let wordStart = 1.0
        /// Inside a word, as the query's first chunk: a substring ("pot" in Spotify).
        static let inWord = 0.4
        /// Inside a word after a skip: a scattered hit ("d" of "mind" in Minimized). Its
        /// characters count for nothing, and starting it costs `scatterPenalty`.
        static let scattered = 0.0
        /// Large enough that any match with a scattered chunk scores below every
        /// word-anchored one, whatever the query's length.
        static let scatterPenalty = 0.5
        /// Skipping text between chunks.
        static let gapOpen = 0.04
        static let gapPerCharacter = 0.002
    }

    /// The best alignment of `query` in `text` as an in-order subsequence, scored by
    /// its chunks (see `Chunk`) and normalized to 0...1: 90% from the chunks (an
    /// unbroken match from the start is the maximum) and 10% from how much of the
    /// text the query covers, which prefers the shorter of otherwise equal titles.
    /// An exact match scores 1. Nil when `query` isn't a subsequence of `text`.
    static func align(
        _ query: [UInt32], in text: SearchText, wantIndices: Bool
    ) -> (quality: Double, indices: [Int])? {
        guard !query.isEmpty else { return (1, []) }
        guard query.count <= text.codes.count else { return nil }
        // Raw buffers keep the per-keystroke loops cheap in debug builds too.
        let best = query.withUnsafeBufferPointer { query in
            text.codes.withUnsafeBufferPointer { codes in
                text.wordStarts.withUnsafeBufferPointer { wordStarts in
                    Alignment(query: query, codes: codes, wordStarts: wordStarts).best(wantIndices: wantIndices)
                }
            }
        }
        guard let best else { return nil }
        let chunks = max(0, min(best.score, Chunk.textStart)) / Chunk.textStart
        let coverage = Double(query.count) / Double(text.codes.count)
        return (0.9 * chunks + 0.1 * coverage, best.indices)
    }
}

/// Dynamic program over (query character, text position, chunk kind): each cell holds
/// the best score of the query's prefix ending at that position in a chunk of that
/// kind. Kinds, in cell order: text start, word start, in word, scattered. Two rows
/// of scores are live at a time; when indices are wanted every cell also records
/// the cell it came from, to trace the winning alignment back for highlighting.
private struct Alignment {
    private static let kinds = 4

    let query: UnsafeBufferPointer<UInt32>
    let codes: UnsafeBufferPointer<UInt32>
    let wordStarts: UnsafeBufferPointer<Bool>

    /// The best score and, when wanted, its text positions; nil when the query isn't
    /// a subsequence of the text.
    func best(wantIndices: Bool) -> (score: Double, indices: [Int])? {
        if opensText {
            return (FuzzyMatcher.Chunk.textStart, wantIndices ? Array(query.indices) : [])
        }
        if query.count == 1 { return bestSingle() }
        let first = UnsafeMutableBufferPointer<Int>.allocate(capacity: query.count)
        let last = UnsafeMutableBufferPointer<Int>.allocate(capacity: query.count)
        defer {
            first.deallocate()
            last.deallocate()
        }
        guard findWindow(first: first, last: last) else { return nil }
        var table = Table(query: query.count, length: codes.count, tracing: wantIndices)
        defer { table.deallocate() }
        for kind in 0 ..< Self.kinds {
            table.credits[kind] = credit(kind)
        }
        fillFirstRow(&table, first[0], last[0])
        for row in 1 ..< query.count {
            fillRow(row, &table, sources: first[row - 1] ... last[row - 1], columns: first[row] ... last[row])
        }
        var best = (score: -Double.infinity, cell: 0)
        for column in first[query.count - 1] ... last[query.count - 1] {
            for kind in 0 ..< Self.kinds where table.current[column * Self.kinds + kind] > best.score {
                best = (table.current[column * Self.kinds + kind], column * Self.kinds + kind)
            }
        }
        return (best.score, wantIndices ? table.trace(endingAt: best.cell, rows: query.count) : [])
    }

    /// The whole query opens the text: the highest score there is.
    private var opensText: Bool {
        for index in query.indices where codes[index] != query[index] {
            return false
        }
        return true
    }

    /// One character: its best place is the first word start holding it, else the
    /// first place at all (the text's own start is `opensText`).
    private func bestSingle() -> (score: Double, indices: [Int])? {
        var fallback: Int?
        for column in codes.indices where codes[column] == query[0] {
            if wordStarts[column] { return (FuzzyMatcher.Chunk.wordStart, [column]) }
            if fallback == nil { fallback = column }
        }
        return fallback.map { (FuzzyMatcher.Chunk.inWord, [$0]) }
    }

    /// Greedy earliest and latest positions per query character; false when the query
    /// isn't a subsequence.
    private func findWindow(first: UnsafeMutableBufferPointer<Int>, last: UnsafeMutableBufferPointer<Int>) -> Bool {
        var position = 0
        for index in query.indices {
            while position < codes.count, codes[position] != query[index] {
                position += 1
            }
            guard position < codes.count else { return false }
            first[index] = position
            position += 1
        }
        position = codes.count - 1
        for index in query.indices.reversed() {
            while codes[position] != query[index] {
                position -= 1
            }
            last[index] = position
            position -= 1
        }
        return true
    }

    private func credit(_ kind: Int) -> Double {
        let credit = switch kind {
        case 0: FuzzyMatcher.Chunk.textStart
        case 1: FuzzyMatcher.Chunk.wordStart
        case 2: FuzzyMatcher.Chunk.inWord
        default: FuzzyMatcher.Chunk.scattered
        }
        return credit / Double(query.count)
    }

    private func fillFirstRow(_ table: inout Table, _ firstColumn: Int, _ lastColumn: Int) {
        table.startRow(firstColumn ... lastColumn)
        for column in firstColumn ... lastColumn where codes[column] == query[0] {
            let kind = column == 0 ? 0 : wordStarts[column] ? 1 : 2
            table.current[column * Self.kinds + kind] = credit(kind)
        }
    }

    private func fillRow(_ row: Int, _ table: inout Table, sources: ClosedRange<Int>, columns: ClosedRange<Int>) {
        guard let codes = codes.baseAddress, let wordStarts = wordStarts.baseAddress else { return }
        table.startRow(columns)
        var fill = RowFill(
            table: table, codes: codes, wordStarts: wordStarts, length: self.codes.count, row: row,
            code: query[row], previousCode: query[row - 1], sources: sources,
            wordJump: credit(1) - FuzzyMatcher.Chunk.gapOpen,
            scatteredJump: credit(3) - FuzzyMatcher.Chunk.gapOpen - FuzzyMatcher.Chunk.scatterPenalty
        )
        fill.run(columns)
    }
}

/// One row of `Alignment`'s table. Base-address pointers and `while` loops: range
/// iterators and checked buffer subscripts are calls in debug builds, and this is the
/// innermost loop.
private struct RowFill {
    private static let kinds = 4
    private static let gapStep = FuzzyMatcher.Chunk.gapPerCharacter

    let table: Table
    let codes: UnsafePointer<UInt32>
    let wordStarts: UnsafePointer<Bool>
    let length: Int
    let row: Int
    let code: UInt32
    let previousCode: UInt32
    let sources: ClosedRange<Int>
    /// Credit for a character opening a chunk after a jump, net of the gap's opening.
    let wordJump: Double
    let scatteredJump: Double
    /// Best earlier cell to jump from, held as score + gapStep × column so that
    /// subtracting gapStep × (column − 1) charges the skipped characters.
    private var jumpScore = -Double.infinity
    private var jumpCell = -1
    private var nextSource: Int

    init(
        table: Table, codes: UnsafePointer<UInt32>, wordStarts: UnsafePointer<Bool>, length: Int, row: Int,
        code: UInt32, previousCode: UInt32, sources: ClosedRange<Int>, wordJump: Double, scatteredJump: Double
    ) {
        self.table = table
        self.codes = codes
        self.wordStarts = wordStarts
        self.length = length
        self.row = row
        self.code = code
        self.previousCode = previousCode
        self.sources = sources
        self.wordJump = wordJump
        self.scatteredJump = scatteredJump
        nextSource = sources.lowerBound
    }

    private var rowBase: Int {
        row * length * Self.kinds
    }

    mutating func run(_ columns: ClosedRange<Int>) {
        var column = columns.lowerBound
        while column <= columns.upperBound {
            absorbSources(upTo: column - 2)
            if codes[column] == code {
                extendChunk(at: column)
                openChunk(at: column)
            }
            column += 1
        }
    }

    /// Takes the previous row's cells up to `last` into the best jump.
    private mutating func absorbSources(upTo last: Int) {
        let previous = table.previous
        while nextSource <= last, nextSource <= sources.upperBound {
            if codes[nextSource] == previousCode {
                var kind = 0
                while kind < Self.kinds {
                    let score = previous[nextSource * Self.kinds + kind] + Self.gapStep * Double(nextSource)
                    if score > jumpScore {
                        jumpScore = score
                        jumpCell = nextSource * Self.kinds + kind
                    }
                    kind += 1
                }
            }
            nextSource += 1
        }
    }

    /// Extends the chunks ending just before `column`; each keeps its kind.
    private func extendChunk(at column: Int) {
        guard column - 1 <= sources.upperBound, codes[column - 1] == previousCode else { return }
        let cell = column * Self.kinds
        var kind = 0
        while kind < Self.kinds {
            let source = cell - Self.kinds + kind
            if table.previous[source] > -.infinity {
                table.current[cell + kind] = table.previous[source] + table.credits[kind]
                table.origins?[rowBase + cell + kind] = Int32(rowBase - length * Self.kinds + source)
            }
            kind += 1
        }
    }

    /// Opens a chunk at `column` after a jump, if that beats extending one.
    private func openChunk(at column: Int) {
        guard jumpCell >= 0 else { return }
        let kind = wordStarts[column] ? 1 : 3
        let score = jumpScore - Self.gapStep * Double(column - 1) + (kind == 1 ? wordJump : scatteredJump)
        let cell = column * Self.kinds + kind
        guard score > table.current[cell] else { return }
        table.current[cell] = score
        table.origins?[rowBase + cell] = Int32(rowBase - length * Self.kinds + jumpCell)
    }
}

/// Score rows (previous and current) and, when tracing, every cell's origin as an
/// index over all rows.
private struct Table {
    let length: Int
    private(set) var previous: UnsafeMutablePointer<Double>
    private(set) var current: UnsafeMutablePointer<Double>
    let origins: UnsafeMutablePointer<Int32>?
    /// Per-character credit of each chunk kind for this query's length.
    let credits: UnsafeMutablePointer<Double>

    init(query: Int, length: Int, tracing: Bool) {
        self.length = length
        previous = .allocate(capacity: length * 4)
        current = .allocate(capacity: length * 4)
        origins = tracing ? .allocate(capacity: query * length * 4) : nil
        credits = .allocate(capacity: 4)
    }

    /// Makes the current row the previous one and clears the new current row over
    /// `columns`, the only part of it that gets read.
    mutating func startRow(_ columns: ClosedRange<Int>) {
        swap(&previous, &current)
        (current + columns.lowerBound * 4).update(repeating: -.infinity, count: columns.count * 4)
    }

    /// Text positions of the alignment ending at `cell` of the last row.
    func trace(endingAt cell: Int, rows: Int) -> [Int] {
        guard let origins else { return [] }
        var positions = [Int](repeating: 0, count: rows)
        var current = (rows - 1) * length * 4 + cell
        for row in (0 ..< rows).reversed() {
            positions[row] = (current / 4) % length
            if row > 0 { current = Int(origins[current]) }
        }
        return positions
    }

    func deallocate() {
        previous.deallocate()
        current.deallocate()
        origins?.deallocate()
        credits.deallocate()
    }
}
