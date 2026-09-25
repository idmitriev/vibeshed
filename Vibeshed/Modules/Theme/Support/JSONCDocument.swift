import Foundation

/// Edits top-level keys of a JSON-with-comments settings file (VS Code, Zed, Claude Code)
/// in place. Everything outside the value being replaced — comments, trailing commas,
/// key order, indentation — is left byte-for-byte intact, unlike a round trip through
/// `JSONSerialization`, which rejects comments and reformats the whole file.
struct JSONCDocument {
    private(set) var text: String

    init(text: String?) {
        let text = text ?? ""
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{\n}\n" : text
    }

    enum EditError: LocalizedError {
        case malformed

        var errorDescription: String? {
            "settings file is not a JSON object"
        }
    }

    /// The parsed value of a top-level key; nil when absent or unparsable.
    func value(forKey key: String) -> Any? {
        let bytes = Array(text.utf8)
        var scanner = Scanner(bytes: bytes)
        guard let member = scanner.scanMembers()?.members.first(where: { $0.key == key }) else {
            return nil
        }
        let raw = Array(bytes[member.valueStart ..< member.valueEnd])
        let cleaned = JSONFormatting.stripCommentsAndTrailingCommas(raw)
        return try? JSONSerialization.jsonObject(with: Data(cleaned), options: .fragmentsAllowed)
    }

    /// Sets (replaces or appends) a top-level key.
    mutating func setValue(_ value: Any, forKey key: String) throws {
        var bytes = Array(text.utf8)
        var scanner = Scanner(bytes: bytes)
        guard let scan = scanner.scanMembers() else { throw EditError.malformed }
        let indent = scan.indent ?? "  "
        let serialized = try JSONFormatting.pretty(value, indent: indent)

        if let member = scan.members.first(where: { $0.key == key }) {
            bytes.replaceSubrange(member.valueStart ..< member.valueEnd, with: Array(serialized.utf8))
        } else {
            let entry = Array("\n\(indent)\(JSONFormatting.quoted(key)): \(serialized)".utf8)
            // Insert after the last non-whitespace byte before the closing brace…
            var insertAt = scan.closeBrace
            while insertAt > scan.openBrace + 1, Scanner.isWhitespace(bytes[insertAt - 1]) {
                insertAt -= 1
            }
            bytes.insert(contentsOf: entry, at: insertAt)
            // …and make sure the previous member is followed by a comma.
            if let last = scan.members.last, !scan.hasTrailingComma {
                bytes.insert(UInt8(ascii: ","), at: last.valueEnd)
            } else if scan.members.isEmpty {
                let closeIndex = insertAt + entry.count
                if closeIndex < bytes.count, bytes[closeIndex] == UInt8(ascii: "}") {
                    bytes.insert(UInt8(ascii: "\n"), at: closeIndex)
                }
            }
        }
        text = String(bytes: bytes, encoding: .utf8) ?? text
    }

    // MARK: - Scanner

    private struct Member {
        let key: String
        let valueStart: Int
        let valueEnd: Int
    }

    private struct Scan {
        var members: [Member] = []
        var openBrace = 0
        var closeBrace = 0
        var hasTrailingComma = false
        var indent: String?
    }

    /// Byte-level scanner. Structural characters are all ASCII, so working on UTF-8
    /// bytes is exact; multi-byte characters only ever appear inside strings/comments.
    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(bytes: [UInt8]) {
            self.bytes = bytes
        }

        static func isWhitespace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }

        var current: UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        mutating func scanMembers() -> Scan? {
            var scan = Scan()
            skipTrivia()
            guard current == UInt8(ascii: "{") else { return nil }
            scan.openBrace = index
            index += 1
            while true {
                skipTrivia()
                guard let byte = current else { return nil }
                if byte == UInt8(ascii: "}") {
                    scan.closeBrace = index
                    return scan
                }
                guard byte == UInt8(ascii: "\"") else { return nil }
                if scan.indent == nil { scan.indent = indentation(before: index) }
                guard let key = readString() else { return nil }
                skipTrivia()
                guard current == UInt8(ascii: ":") else { return nil }
                index += 1
                skipTrivia()
                let valueStart = index
                guard skipValue() else { return nil }
                scan.members.append(Member(key: key, valueStart: valueStart, valueEnd: index))
                skipTrivia()
                scan.hasTrailingComma = false
                if current == UInt8(ascii: ",") {
                    index += 1
                    scan.hasTrailingComma = true
                }
            }
        }

        private func indentation(before position: Int) -> String? {
            var start = position
            while start > 0, bytes[start - 1] == 0x20 || bytes[start - 1] == 0x09 {
                start -= 1
            }
            guard start < position, start == 0 || bytes[start - 1] == 0x0A else { return nil }
            return String(bytes: bytes[start ..< position], encoding: .utf8)
        }

        mutating func skipTrivia() {
            while let byte = current {
                if Self.isWhitespace(byte) {
                    index += 1
                } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "/") {
                    while let next = current, next != 0x0A {
                        index += 1
                    }
                } else if byte == UInt8(ascii: "/"), index + 1 < bytes.count, bytes[index + 1] == UInt8(ascii: "*") {
                    index = JSONFormatting.blockCommentEnd(bytes, from: index + 2)
                } else {
                    return
                }
            }
        }

        /// Reads a string starting at the opening quote; returns its decoded value.
        mutating func readString() -> String? {
            let start = index
            guard skipString() else { return nil }
            let literal = Data(bytes[start ..< index])
            return (try? JSONSerialization.jsonObject(with: literal, options: .fragmentsAllowed)) as? String
        }

        mutating func skipString() -> Bool {
            index += 1
            while let byte = current {
                index += 1
                if byte == UInt8(ascii: "\\") {
                    index += 1
                } else if byte == UInt8(ascii: "\"") {
                    return true
                }
            }
            return false
        }

        /// Skips one value, leaving `index` just past it.
        mutating func skipValue() -> Bool {
            guard let byte = current else { return false }
            if byte == UInt8(ascii: "\"") { return skipString() }
            if byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[") { return skipContainer() }
            let terminators: Set<UInt8> = [UInt8(ascii: ","), UInt8(ascii: "}"), UInt8(ascii: "]"), UInt8(ascii: "/")]
            let start = index
            while let next = current, !terminators.contains(next), !Self.isWhitespace(next) {
                index += 1
            }
            return index > start
        }

        /// Skips a balanced `{…}` / `[…]`, stepping over strings and comments.
        private mutating func skipContainer() -> Bool {
            var depth = 0
            while let next = current {
                if next == UInt8(ascii: "\"") {
                    guard skipString() else { return false }
                    continue
                }
                if next == UInt8(ascii: "/") {
                    let before = index
                    skipTrivia()
                    if index == before { index += 1 }
                    continue
                }
                if next == UInt8(ascii: "{") || next == UInt8(ascii: "[") {
                    depth += 1
                } else if next == UInt8(ascii: "}") || next == UInt8(ascii: "]") {
                    depth -= 1
                    if depth == 0 {
                        index += 1
                        return true
                    }
                }
                index += 1
            }
            return false
        }
    }
}

// MARK: - Formatting

enum JSONFormatting {
    /// Pretty JSON with `"key": value` spacing (Foundation emits `"key" : value`),
    /// continuation lines prefixed with `indent` so nested objects line up.
    static func pretty(_ value: Any, indent: String = "") throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        )
        let text = tightenColons(String(bytes: data, encoding: .utf8) ?? "")
        guard !indent.isEmpty else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\n\(indent)")
    }

    static func quoted(_ key: String) -> String {
        let escaped = key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// `"key" : value` → `"key": value`. A `" : ` sequence can only occur inside a string
    /// after an escaped quote, so those (preceded by `\`) are left alone.
    private static func tightenColons(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var previous: Character?
        var iterator = text.makeIterator()
        var pending: [Character] = []
        while let char = iterator.next() {
            pending.append(char)
            if pending.count == 4 {
                if pending == ["\"", " ", ":", " "], previous != "\\" {
                    result += "\": "
                    previous = " "
                    pending = []
                    continue
                }
                let first = pending.removeFirst()
                result.append(first)
                previous = first
            }
        }
        result += String(pending)
        return result
    }

    /// Index just past the `*/` closing a block comment whose body starts at `start`.
    static func blockCommentEnd(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index + 1 < bytes.count {
            if bytes[index] == UInt8(ascii: "*"), bytes[index + 1] == UInt8(ascii: "/") { return index + 2 }
            index += 1
        }
        return bytes.count
    }

    /// Removes `//` and `/* */` comments and trailing commas so Foundation can parse JSONC.
    static func stripCommentsAndTrailingCommas(_ bytes: [UInt8]) -> [UInt8] {
        removeTrailingCommas(removeComments(bytes))
    }

    private static func removeComments(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        var inString = false
        while index < bytes.count {
            let byte = bytes[index]
            let next = index + 1 < bytes.count ? bytes[index + 1] : 0
            if inString {
                output.append(byte)
                if byte == UInt8(ascii: "\\"), index + 1 < bytes.count {
                    output.append(next)
                    index += 1
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
                index += 1
            } else if byte == UInt8(ascii: "/"), next == UInt8(ascii: "/") {
                while index < bytes.count, bytes[index] != 0x0A {
                    index += 1
                }
            } else if byte == UInt8(ascii: "/"), next == UInt8(ascii: "*") {
                index = blockCommentEnd(bytes, from: index + 2)
            } else {
                inString = byte == UInt8(ascii: "\"")
                output.append(byte)
                index += 1
            }
        }
        return output
    }

    /// Drops commas that only whitespace separates from a closing `}` / `]` (comment-free input).
    private static func removeTrailingCommas(_ bytes: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var inString = false
        var escaped = false
        for byte in bytes {
            if inString {
                if escaped {
                    escaped = false
                } else if byte == UInt8(ascii: "\\") {
                    escaped = true
                } else if byte == UInt8(ascii: "\"") {
                    inString = false
                }
            } else if byte == UInt8(ascii: "\"") {
                inString = true
            } else if byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]") {
                var back = output.count - 1
                while back >= 0, [0x20, 0x09, 0x0A, 0x0D].contains(output[back]) {
                    back -= 1
                }
                if back >= 0, output[back] == UInt8(ascii: ",") { output.remove(at: back) }
            }
            output.append(byte)
        }
        return output
    }
}
