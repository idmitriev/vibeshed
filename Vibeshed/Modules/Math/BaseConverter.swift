import Foundation

enum BaseConverter {
    struct ConversionResult: Sendable {
        let original: String
        let fromBase: String
        let results: [(base: String, value: String)]
    }

    // MARK: - Parsing

    static func parse(_ query: String) -> ConversionResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        // Pattern: "{value} to {base}"
        if let result = parseExplicitConversion(trimmed) {
            return result
        }

        // Prefix detection: 0x, 0b, 0o
        if let result = parsePrefixLiteral(trimmed) {
            return result
        }

        return nil
    }

    /// For integer expression results, generate base conversions
    static func convertInteger(_ value: Int) -> ConversionResult? {
        guard value >= 0, value <= Int.max / 2 else { return nil }
        return ConversionResult(
            original: "\(value)",
            fromBase: "dec",
            results: allBases(for: value, excluding: "dec")
        )
    }

    // MARK: - Explicit Conversion

    // swiftlint:disable force_try
    private static let explicitPattern = try! NSRegularExpression(
        pattern: #"^(0x[0-9a-f]+|0b[01]+|0o[0-7]+|\d+)\s+to\s+(hex|dec|bin|oct|binary|decimal|octal|hexadecimal)$"#,
        options: [.caseInsensitive]
    )
    // swiftlint:enable force_try

    private static func parseExplicitConversion(_ input: String) -> ConversionResult? {
        let range = NSRange(input.startIndex..., in: input)
        guard let match = explicitPattern.firstMatch(in: input, range: range),
              match.numberOfRanges == 3
        else { return nil }

        guard let valueRange = Range(match.range(at: 1), in: input),
              Range(match.range(at: 2), in: input) != nil
        else { return nil }

        let valueStr = String(input[valueRange])

        guard let intValue = parseIntValue(valueStr) else { return nil }
        let fromBase = detectBase(valueStr)

        return ConversionResult(
            original: valueStr,
            fromBase: fromBase,
            results: allBases(for: intValue, excluding: nil)
        )
    }

    // MARK: - Prefix Literals

    private static func parsePrefixLiteral(_ input: String) -> ConversionResult? {
        // Only match clean literals with no extra text
        guard !input.contains(" ") else { return nil }

        let fromBase: String
        if input.hasPrefix("0x") {
            fromBase = "hex"
        } else if input.hasPrefix("0b") {
            fromBase = "bin"
        } else if input.hasPrefix("0o") {
            fromBase = "oct"
        } else {
            return nil
        }

        guard let intValue = parseIntValue(input) else { return nil }

        return ConversionResult(
            original: input,
            fromBase: fromBase,
            results: allBases(for: intValue, excluding: fromBase)
        )
    }

    // MARK: - Helpers

    private static func parseIntValue(_ str: String) -> Int? {
        if str.hasPrefix("0x") {
            return Int(str.dropFirst(2), radix: 16)
        } else if str.hasPrefix("0b") {
            return Int(str.dropFirst(2), radix: 2)
        } else if str.hasPrefix("0o") {
            return Int(str.dropFirst(2), radix: 8)
        } else {
            return Int(str)
        }
    }

    private static func detectBase(_ str: String) -> String {
        if str.hasPrefix("0x") { return "hex" }
        if str.hasPrefix("0b") { return "bin" }
        if str.hasPrefix("0o") { return "oct" }
        return "dec"
    }

    private static func normalizeBase(_ str: String) -> String {
        switch str.lowercased() {
        case "hex", "hexadecimal": return "hex"
        case "bin", "binary": return "bin"
        case "oct", "octal": return "oct"
        case "dec", "decimal": return "dec"
        default: return str
        }
    }

    private static func allBases(
        for value: Int, excluding: String?
    ) -> [(base: String, value: String)] {
        var results: [(base: String, value: String)] = []
        if excluding != "dec" {
            results.append((base: "Decimal", value: "\(value)"))
        }
        if excluding != "hex" {
            results.append((base: "Hex", value: "0x\(String(value, radix: 16, uppercase: true))"))
        }
        if excluding != "bin" {
            results.append((base: "Binary", value: "0b\(String(value, radix: 2))"))
        }
        if excluding != "oct" {
            results.append((base: "Octal", value: "0o\(String(value, radix: 8))"))
        }
        return results
    }
}
