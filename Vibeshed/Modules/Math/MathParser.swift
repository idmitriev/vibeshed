import Foundation

enum MathParser {
    enum ParseResult: Sendable {
        case expression(expression: String, result: Double)
        case unitConversion(
            value: Double, fromUnit: String, fromUnitFull: String,
            toUnit: String, toUnitFull: String, result: Double, category: String
        )
        case currencyConversion(
            value: Double, fromCurrency: String,
            toCurrency: String, result: Double
        )
        case percentage(value: Double, ofValue: Double, result: Double)
        case baseConversion(original: String, fromBase: String, results: [(base: String, value: String)])
    }

    // MARK: - Main Dispatch

    static func parse(
        _ query: String,
        currencyRates: [String: Double]?
    ) -> [ParseResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [ParseResult] = []

        // 1. Percentage
        if let pct = parsePercentage(trimmed) {
            results.append(pct)
        }

        // 2. Base conversion (prefix literals and explicit)
        if let base = BaseConverter.parse(trimmed) {
            results.append(.baseConversion(
                original: base.original,
                fromBase: base.fromBase,
                results: base.results
            ))
        }

        // 3. Unit conversion (requires "to/in" keyword)
        if let unit = UnitConverter.parse(trimmed) {
            results.append(.unitConversion(
                value: unit.value,
                fromUnit: unit.fromUnit,
                fromUnitFull: unit.fromUnitFull,
                toUnit: unit.toUnit,
                toUnitFull: unit.toUnitFull,
                result: unit.result,
                category: unit.category
            ))
        }

        // 4. Currency conversion
        if let rates = currencyRates,
           let req = CurrencyConverter.parse(trimmed),
           let converted = CurrencyConverter.convert(req, rates: rates)
        {
            results.append(.currencyConversion(
                value: req.value,
                fromCurrency: req.fromCurrency,
                toCurrency: req.toCurrency,
                result: converted
            ))
        }

        // 5. Expression evaluation (skip if already matched as conversion/base)
        let hasConversion = results.contains { r in
            switch r {
            case .unitConversion, .currencyConversion: return true
            default: return false
            }
        }
        if !hasConversion, let val = ExpressionParser.evaluate(trimmed) {
            results.append(.expression(expression: trimmed, result: val))

            // For integer results, offer base conversions
            if val == val.rounded(), val >= 0, val <= Double(Int.max / 2),
               !results.contains(where: { if case .baseConversion = $0 { return true }; return false }),
               ExpressionParser.isNonTrivial(trimmed)
            {
                if let base = BaseConverter.convertInteger(Int(val)) {
                    results.append(.baseConversion(
                        original: formatNumber(val, decimalPlaces: 0),
                        fromBase: base.fromBase,
                        results: base.results
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Percentage Parser

    // swiftlint:disable force_try
    private static let percentagePattern = try! NSRegularExpression(
        pattern: #"^(?:what\s+is\s+)?(\d+(?:\.\d+)?)\s*%\s*(?:of)\s+(\d+(?:\.\d+)?)$"#,
        options: [.caseInsensitive]
    )
    // swiftlint:enable force_try

    private static func parsePercentage(_ input: String) -> ParseResult? {
        let range = NSRange(input.startIndex..., in: input)
        guard let match = percentagePattern.firstMatch(in: input, range: range),
              match.numberOfRanges == 3
        else { return nil }

        guard let pctRange = Range(match.range(at: 1), in: input),
              let ofRange = Range(match.range(at: 2), in: input)
        else { return nil }

        guard let pctValue = Double(String(input[pctRange])),
              let ofValue = Double(String(input[ofRange]))
        else { return nil }

        let result = pctValue / 100.0 * ofValue
        return .percentage(value: pctValue, ofValue: ofValue, result: result)
    }

    // MARK: - Number Formatting

    static func formatNumber(_ value: Double, decimalPlaces: Int) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            formatter.usesGroupingSeparator = true
            return formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = decimalPlaces
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
