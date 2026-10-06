import Foundation

/// Reverses romaji input: "さふぁり" → "safari", "てｒみなｌ" → "terminal".
///
/// Japanese IMEs turn typed romaji into kana as you type and leave keys that start
/// no kana as full-width Latin. Several spellings make the same kana (し is "si",
/// "shi" or "ci"), so this yields a few readings, the most likely first.
enum JapaneseRomaji {
    /// Upper bound on readings, so long ambiguous queries stay cheap to score.
    static let maxReadings = 8

    /// Latin readings of `query`; empty when it holds no kana.
    static func readings(of query: String) -> [String] {
        let text = Array(hiragana(query.precomposedStringWithCompatibilityMapping))
        guard text.contains(where: isKana) else { return [] }

        var segments: [[String]] = []
        var index = 0
        while index < text.count {
            let ch = text[index]
            let next = index + 1 < text.count ? text[index + 1] : nil

            if let next, let pair = pairs[String([ch, next])] {
                segments.append(pair)
                index += 2
            } else if let next, "ゃゅょ".contains(next), let base = single[ch], let yoon = yoon(base, next) {
                segments.append(yoon)
                index += 2
            } else if ch == "っ", let next, next.isASCII, next.isLetter {
                // A doubled consonant: "app" shows as あっｐ.
                segments.append([String(next)])
                index += 1
            } else if ch == "ん" {
                // "n" alone only makes ん before a key that can't extend it.
                let needsDouble = next.map { "あいうえおやゆよなにぬねの".contains($0) } ?? false
                segments.append([needsDouble ? "nn" : "n"])
                index += 1
            } else {
                segments.append(single[ch] ?? [String(ch)])
                index += 1
            }
        }
        segments = doubleAfterSokuon(segments)

        var results = [""]
        for alternatives in segments {
            results = Array(results.lazy.flatMap { prefix in alternatives.map { prefix + $0 } }.prefix(maxReadings))
        }
        return results
    }

    /// っ before a kana doubles that kana's leading consonant ("きって" → "kitte").
    private static func doubleAfterSokuon(_ segments: [[String]]) -> [[String]] {
        var out: [[String]] = []
        var pendingSokuon = false
        for segment in segments {
            if segment == ["ltu"] {
                if pendingSokuon { out.append(["ltu"]) }
                pendingSokuon = true
                continue
            }
            if pendingSokuon {
                let doubled = segment.compactMap { alt -> String? in
                    guard let first = alt.first, first.isLetter, !"aiueon".contains(first) else { return nil }
                    return String(first) + alt
                }
                out.append(doubled.isEmpty ? ["ltu"] : doubled)
                if doubled.isEmpty { out.append(segment) }
                pendingSokuon = false
            } else {
                out.append(segment)
            }
        }
        if pendingSokuon { out.append(["ltu"]) }
        return out
    }

    /// きゃ → "kya", しゃ → "sya"/"sha", じゃ → "zya"/"ja".
    private static func yoon(_ base: [String], _ small: Character) -> [String]? {
        guard base.allSatisfy({ $0.hasSuffix("i") }), base.first != "i" else { return nil }
        let vowel = ["ゃ": "a", "ゅ": "u", "ょ": "o"][String(small)] ?? "a"
        var result: [String] = []
        for alt in base where !alt.hasPrefix("c") || alt.hasPrefix("ch") {
            let stem = alt.dropLast()
            let reading = String(stem) + (stem.hasSuffix("h") || stem == "j" ? vowel : "y" + vowel)
            if !result.contains(reading) { result.append(reading) }
        }
        return result.isEmpty ? nil : result
    }

    private static func isKana(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { (0x3041 ... 0x3096).contains($0.value) }
    }

    /// Katakana → hiragana, so one table serves both.
    private static func hiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1 ... 0x30F6).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x60) ?? scalar : scalar
        }))
    }

    // MARK: - Tables

    /// Kana a consonant + small vowel make together.
    private static let pairs: [String: [String]] = [
        "ふぁ": ["fa"], "ふぃ": ["fi"], "ふぇ": ["fe"], "ふぉ": ["fo"],
        "ゔぁ": ["va"], "ゔぃ": ["vi"], "ゔぇ": ["ve"], "ゔぉ": ["vo"],
        "くぁ": ["qa"], "くぃ": ["qi"], "くぇ": ["qe"], "くぉ": ["qo"],
        "てぃ": ["thi"], "でぃ": ["dhi"], "てゅ": ["thu"], "でゅ": ["dhu"],
        "うぃ": ["wi"], "うぇ": ["we"], "しぇ": ["she"], "じぇ": ["je"], "ちぇ": ["che"],
    ]

    /// Each kana's spellings, most common in English-ish typing first.
    private static let single: [Character: [String]] = {
        var table: [Character: [String]] = [:]
        let rows: [(String, [[String]])] = [
            ("あいうえお", [["a"], ["i"], ["u"], ["e"], ["o"]]),
            ("かきくけこ", [["ka", "ca"], ["ki"], ["ku", "cu"], ["ke"], ["ko", "co"]]),
            ("さしすせそ", [["sa"], ["si", "shi", "ci"], ["su"], ["se", "ce"], ["so"]]),
            ("たちつてと", [["ta"], ["ti", "chi"], ["tu", "tsu"], ["te"], ["to"]]),
            ("なにぬねの", [["na"], ["ni"], ["nu"], ["ne"], ["no"]]),
            ("はひふへほ", [["ha"], ["hi"], ["hu", "fu"], ["he"], ["ho"]]),
            ("まみむめも", [["ma"], ["mi"], ["mu"], ["me"], ["mo"]]),
            ("やゆよわを", [["ya"], ["yu"], ["yo"], ["wa"], ["wo"]]),
            ("らりるれろ", [["ra"], ["ri"], ["ru"], ["re"], ["ro"]]),
            ("がぎぐげご", [["ga"], ["gi"], ["gu"], ["ge"], ["go"]]),
            ("ざじずぜぞ", [["za"], ["zi", "ji"], ["zu"], ["ze"], ["zo"]]),
            ("だぢづでど", [["da"], ["di"], ["du"], ["de"], ["do"]]),
            ("ばびぶべぼ", [["ba"], ["bi"], ["bu"], ["be"], ["bo"]]),
            ("ぱぴぷぺぽ", [["pa"], ["pi"], ["pu"], ["pe"], ["po"]]),
            ("ぁぃぅぇぉ", [["la"], ["li"], ["lu"], ["le"], ["lo"]]),
            ("ゃゅょっゎ", [["lya"], ["lyu"], ["lyo"], ["ltu"], ["lwa"]]),
            ("ゔー、。・", [["vu"], ["-"], [","], ["."], ["/"]]),
            ("「」〜", [["["], ["]"], ["~"]]),
        ]
        for (kana, spellings) in rows {
            for (ch, alts) in zip(kana, spellings) {
                table[ch] = alts
            }
        }
        return table
    }()
}
