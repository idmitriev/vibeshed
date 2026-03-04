import Foundation

enum UnitConverter {
    struct ConversionResult: Sendable {
        let value: Double
        let fromUnit: String
        let fromUnitFull: String
        let toUnit: String
        let toUnitFull: String
        let result: Double
        let category: String
    }

    // MARK: - Unit Data

    private struct UnitInfo {
        let category: String
        let factor: Double
        let fullName: String
    }

    // swiftlint:disable function_body_length
    private static let units: [String: UnitInfo] = {
        var u: [String: UnitInfo] = [:]

        func add(_ names: [String], cat: String, factor: Double, full: String) {
            for name in names {
                u[name] = UnitInfo(category: cat, factor: factor, fullName: full)
            }
        }

        // Length (base: meters)
        add(["mm", "millimeter", "millimeters"], cat: "Length", factor: 0.001, full: "millimeters")
        add(["cm", "centimeter", "centimeters"], cat: "Length", factor: 0.01, full: "centimeters")
        add(["m", "meter", "meters"], cat: "Length", factor: 1, full: "meters")
        add(["km", "kilometer", "kilometers"], cat: "Length", factor: 1000, full: "kilometers")
        add(["in", "inch", "inches"], cat: "Length", factor: 0.0254, full: "inches")
        add(["ft", "foot", "feet"], cat: "Length", factor: 0.3048, full: "feet")
        add(["yd", "yard", "yards"], cat: "Length", factor: 0.9144, full: "yards")
        add(["mi", "mile", "miles"], cat: "Length", factor: 1609.344, full: "miles")
        add(["nm", "nautical"], cat: "Length", factor: 1852, full: "nautical miles")

        // Weight (base: grams)
        add(["mg", "milligram", "milligrams"], cat: "Weight", factor: 0.001, full: "milligrams")
        add(["g", "gram", "grams"], cat: "Weight", factor: 1, full: "grams")
        add(["kg", "kilogram", "kilograms"], cat: "Weight", factor: 1000, full: "kilograms")
        add(["lb", "lbs", "pound", "pounds"], cat: "Weight", factor: 453.592, full: "pounds")
        add(["oz", "ounce", "ounces"], cat: "Weight", factor: 28.3495, full: "ounces")
        add(["ton", "tons"], cat: "Weight", factor: 907_185, full: "tons")
        add(["tonne", "tonnes"], cat: "Weight", factor: 1_000_000, full: "tonnes")
        add(["st", "stone", "stones"], cat: "Weight", factor: 6350.29, full: "stones")

        // Volume (base: liters)
        add(["ml", "milliliter", "milliliters"], cat: "Volume", factor: 0.001, full: "milliliters")
        add(["l", "liter", "liters", "litre", "litres"], cat: "Volume", factor: 1, full: "liters")
        add(["gal", "gallon", "gallons"], cat: "Volume", factor: 3.78541, full: "gallons")
        add(["qt", "quart", "quarts"], cat: "Volume", factor: 0.946353, full: "quarts")
        add(["pt", "pint", "pints"], cat: "Volume", factor: 0.473176, full: "pints")
        add(["cup", "cups"], cat: "Volume", factor: 0.236588, full: "cups")
        add(["floz"], cat: "Volume", factor: 0.0295735, full: "fluid ounces")
        add(["tbsp", "tablespoon", "tablespoons"], cat: "Volume", factor: 0.0147868, full: "tablespoons")
        add(["tsp", "teaspoon", "teaspoons"], cat: "Volume", factor: 0.00492892, full: "teaspoons")

        // Area (base: square meters)
        add(["mm2", "sqmm"], cat: "Area", factor: 0.000001, full: "mm\u{00B2}")
        add(["cm2", "sqcm"], cat: "Area", factor: 0.0001, full: "cm\u{00B2}")
        add(["m2", "sqm"], cat: "Area", factor: 1, full: "m\u{00B2}")
        add(["km2", "sqkm"], cat: "Area", factor: 1_000_000, full: "km\u{00B2}")
        add(["in2", "sqin"], cat: "Area", factor: 0.00064516, full: "in\u{00B2}")
        add(["ft2", "sqft"], cat: "Area", factor: 0.092903, full: "ft\u{00B2}")
        add(["yd2", "sqyd"], cat: "Area", factor: 0.836127, full: "yd\u{00B2}")
        add(["acre", "acres"], cat: "Area", factor: 4046.86, full: "acres")
        add(["ha", "hectare", "hectares"], cat: "Area", factor: 10000, full: "hectares")

        // Speed (base: m/s)
        add(["mps"], cat: "Speed", factor: 1, full: "m/s")
        add(["kph", "kmh", "kmph"], cat: "Speed", factor: 0.277778, full: "km/h")
        add(["mph"], cat: "Speed", factor: 0.44704, full: "mph")
        add(["knot", "knots", "kt", "kts"], cat: "Speed", factor: 0.514444, full: "knots")
        add(["fps"], cat: "Speed", factor: 0.3048, full: "ft/s")

        // Time (base: seconds)
        add(["ms", "millisecond", "milliseconds"], cat: "Time", factor: 0.001, full: "milliseconds")
        add(["s", "sec", "second", "seconds"], cat: "Time", factor: 1, full: "seconds")
        add(["min", "minute", "minutes"], cat: "Time", factor: 60, full: "minutes")
        add(["h", "hr", "hour", "hours"], cat: "Time", factor: 3600, full: "hours")
        add(["day", "days"], cat: "Time", factor: 86400, full: "days")
        add(["week", "weeks"], cat: "Time", factor: 604_800, full: "weeks")
        add(["month", "months"], cat: "Time", factor: 2_592_000, full: "months")
        add(["year", "years", "yr"], cat: "Time", factor: 31_536_000, full: "years")

        // Data (base: bytes)
        add(["b", "byte", "bytes"], cat: "Data", factor: 1, full: "bytes")
        add(["kb", "kilobyte", "kilobytes"], cat: "Data", factor: 1000, full: "kilobytes")
        add(["mb", "megabyte", "megabytes"], cat: "Data", factor: 1_000_000, full: "megabytes")
        add(["gb", "gigabyte", "gigabytes"], cat: "Data", factor: 1_000_000_000, full: "gigabytes")
        add(["tb", "terabyte", "terabytes"], cat: "Data", factor: 1_000_000_000_000, full: "terabytes")
        add(["pb", "petabyte", "petabytes"], cat: "Data", factor: 1_000_000_000_000_000, full: "petabytes")
        add(["kib", "kibibyte", "kibibytes"], cat: "Data", factor: 1024, full: "kibibytes")
        add(["mib", "mebibyte", "mebibytes"], cat: "Data", factor: 1_048_576, full: "mebibytes")
        add(["gib", "gibibyte", "gibibytes"], cat: "Data", factor: 1_073_741_824, full: "gibibytes")
        add(["tib", "tebibyte", "tebibytes"], cat: "Data", factor: 1_099_511_627_776, full: "tebibytes")

        // Temperature uses special handling
        add(["c", "celsius", "\u{00B0}c"], cat: "Temperature", factor: 0, full: "Celsius")
        add(["f", "fahrenheit", "\u{00B0}f"], cat: "Temperature", factor: 0, full: "Fahrenheit")
        add(["k", "kelvin"], cat: "Temperature", factor: 0, full: "Kelvin")

        return u
    }()
    // swiftlint:enable function_body_length

    // MARK: - Parsing

    // swiftlint:disable force_try
    private static let conversionPattern = try! NSRegularExpression(
        pattern: #"^(-?[\d.,]+)\s*([a-zA-Z\u00B0]{1,20})\s+(?:to|in|as|>)\s+([a-zA-Z\u00B0]{1,20})$"#,
        options: [.caseInsensitive]
    )
    // swiftlint:enable force_try

    static func parse(_ query: String) -> ConversionResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        guard let match = conversionPattern.firstMatch(in: trimmed, range: range),
              match.numberOfRanges == 4
        else { return nil }

        guard let valueRange = Range(match.range(at: 1), in: trimmed),
              let fromRange = Range(match.range(at: 2), in: trimmed),
              let toRange = Range(match.range(at: 3), in: trimmed)
        else { return nil }

        let valueStr = String(trimmed[valueRange]).replacingOccurrences(of: ",", with: "")
        guard let value = Double(valueStr) else { return nil }

        let fromKey = String(trimmed[fromRange]).lowercased()
        let toKey = String(trimmed[toRange]).lowercased()

        guard let fromUnit = units[fromKey],
              let toUnit = units[toKey],
              fromUnit.category == toUnit.category
        else { return nil }

        let result: Double
        if fromUnit.category == "Temperature" {
            guard let r = convertTemperature(value, from: fromKey, to: toKey) else {
                return nil
            }
            result = r
        } else {
            result = value * fromUnit.factor / toUnit.factor
        }

        return ConversionResult(
            value: value,
            fromUnit: fromKey,
            fromUnitFull: fromUnit.fullName,
            toUnit: toKey,
            toUnitFull: toUnit.fullName,
            result: result,
            category: fromUnit.category
        )
    }

    // MARK: - Temperature

    private static func convertTemperature(
        _ value: Double, from: String, to: String
    ) -> Double? {
        let fromBase = temperatureBase(from)
        let toBase = temperatureBase(to)
        guard let fromBase, let toBase, fromBase != toBase else {
            return nil
        }

        // Convert to Celsius first
        let celsius: Double
        switch fromBase {
        case "c": celsius = value
        case "f": celsius = (value - 32) * 5 / 9
        case "k": celsius = value - 273.15
        default: return nil
        }

        // Convert from Celsius to target
        switch toBase {
        case "c": return celsius
        case "f": return celsius * 9 / 5 + 32
        case "k": return celsius + 273.15
        default: return nil
        }
    }

    private static func temperatureBase(_ unit: String) -> String? {
        switch unit {
        case "c", "celsius", "\u{00B0}c": return "c"
        case "f", "fahrenheit", "\u{00B0}f": return "f"
        case "k", "kelvin": return "k"
        default: return nil
        }
    }
}
