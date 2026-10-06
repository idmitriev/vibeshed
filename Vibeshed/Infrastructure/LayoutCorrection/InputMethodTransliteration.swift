import Foundation

/// Recovers the Latin keys behind text typed while an input *method* was active.
///
/// `LayoutTransliterator` reads key → character tables from keyboard layouts, but
/// Korean, Japanese and Zhuyin input methods expose no such table: they compose
/// keystrokes into syllables (Hangul), kana or Bopomofo. These reverse that
/// composition from the text alone, so they work whichever source is active.
enum InputMethodTransliteration {
    struct Candidate: Equatable {
        let text: String
        let language: String
    }

    /// Latin readings of `query`, most likely first; empty when it holds no
    /// Hangul, kana or Bopomofo.
    static func candidates(for query: String) -> [Candidate] {
        if let korean = korean(query) {
            return [Candidate(text: korean, language: "Korean")]
        }
        if let zhuyin = zhuyin(query) {
            return [Candidate(text: zhuyin, language: "Chinese (Zhuyin)")]
        }
        return JapaneseRomaji.readings(of: query).map { Candidate(text: $0, language: "Japanese") }
    }

    // MARK: - Korean (2-Set / Dubeolsik)

    private static let hangulBase: UInt32 = 0xAC00
    private static let hangulLast: UInt32 = 0xD7A3
    private static let leads = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let vowels = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    /// Index 0 is "no final consonant".
    private static let tails: [Character?] = [nil] + "ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ".map { $0 }

    /// Compound jamo are typed as two keys.
    private static let compoundJamo: [Character: String] = [
        "ㅘ": "ㅗㅏ", "ㅙ": "ㅗㅐ", "ㅚ": "ㅗㅣ", "ㅝ": "ㅜㅓ", "ㅞ": "ㅜㅔ", "ㅟ": "ㅜㅣ", "ㅢ": "ㅡㅣ",
        "ㄳ": "ㄱㅅ", "ㄵ": "ㄴㅈ", "ㄶ": "ㄴㅎ", "ㄺ": "ㄹㄱ", "ㄻ": "ㄹㅁ", "ㄼ": "ㄹㅂ",
        "ㄽ": "ㄹㅅ", "ㄾ": "ㄹㅌ", "ㄿ": "ㄹㅍ", "ㅀ": "ㄹㅎ", "ㅄ": "ㅂㅅ",
    ]

    private static let dubeolsikKeys: [Character: Character] = zip(
        "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔㅁㄴㅇㄹㅎㅗㅓㅏㅣㅋㅌㅊㅍㅠㅜㅡㅃㅉㄸㄲㅆㅒㅖ",
        "qwertyuiopasdfghjklzxcvbnmQWERTOP"
    ).reduce(into: [:]) { $0[$1.0] = $1.1 }

    /// "ㅗ디ㅣㅐ" → "hello". Nil when the query holds no Hangul.
    static func korean(_ query: String) -> String? {
        var jamo = ""
        var sawHangul = false
        for ch in query {
            if let scalar = ch.unicodeScalars.first, ch.unicodeScalars.count == 1,
               (hangulBase ... hangulLast).contains(scalar.value)
            {
                let index = Int(scalar.value - hangulBase)
                jamo.append(leads[index / (21 * 28)])
                jamo.append(vowels[(index % (21 * 28)) / 28])
                if let tail = tails[index % 28] { jamo.append(tail) }
                sawHangul = true
            } else {
                if dubeolsikKeys[ch] != nil || compoundJamo[ch] != nil { sawHangul = true }
                jamo.append(ch)
            }
        }
        guard sawHangul else { return nil }

        var keys = ""
        for ch in jamo {
            for part in compoundJamo[ch] ?? String(ch) {
                keys.append(dubeolsikKeys[part] ?? part)
            }
        }
        return keys
    }

    // MARK: - Chinese (Zhuyin / Bopomofo, standard layout)

    private static let zhuyinKeys: [Character: Character] = zip(
        "ㄅㄉˇˋㄓˊ˙ㄚㄞㄢㄦㄆㄊㄍㄐㄔㄗㄧㄛㄟㄣㄇㄋㄎㄑㄕㄘㄨㄜㄠㄤㄈㄌㄏㄒㄖㄙㄩㄝㄡㄥ",
        "1234567890-qwertyuiopasdfghjkl;zxcvbnm,./"
    ).reduce(into: [:]) { $0[$1.0] = $1.1 }

    /// "ㄋㄇㄑㄇㄐㄛ" → "safari". Nil when the query holds no Bopomofo letters.
    static func zhuyin(_ query: String) -> String? {
        // Tone marks alone are also common punctuation; require a Bopomofo letter.
        guard query.unicodeScalars.contains(where: { (0x3105 ... 0x312F).contains($0.value) }) else {
            return nil
        }
        return String(query.map { zhuyinKeys[$0] ?? $0 })
    }
}
