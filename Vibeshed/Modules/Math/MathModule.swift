import Foundation
import OSLog

actor MathModule: ModuleConfigurable {
    let id = "math"
    let displayName = "Math & Conversions"
    let iconName = "function"
    var isEnabled = true

    typealias Config = MathConfig
    static var defaultConfig: Config? { .init() }

    private var config: MathConfig = .init()
    private var context: ModuleContext?
    private var rateCache: CurrencyRateCache?
    private let log = Log.module("math")

    func initialize(context: ModuleContext) async throws {
        self.context = context
        if config.enableCurrency {
            let cache = CurrencyRateCache(
                ttl: TimeInterval(config.currencyRateTTL)
            )
            rateCache = cache
            Task { await cache.fetchIfNeeded() }
        }
        log.info("Math module initialized")
    }

    func configDidUpdate(_ config: MathConfig) async {
        let currencyChanged = config.enableCurrency != self.config.enableCurrency
            || config.currencyRateTTL != self.config.currencyRateTTL
        self.config = config
        if currencyChanged {
            if config.enableCurrency {
                let cache = CurrencyRateCache(
                    ttl: TimeInterval(config.currencyRateTTL)
                )
                rateCache = cache
                Task { await cache.fetchIfNeeded() }
            } else {
                rateCache = nil
            }
        }
        log.debug("Config updated")
    }

    static func validate(_ config: MathConfig) -> ConfigValidationResult {
        var errors: [String] = []
        if config.decimalPlaces < 0 || config.decimalPlaces > 15 {
            errors.append("decimalPlaces must be between 0 and 15")
        }
        if config.currencyRateTTL < 60 {
            errors.append("currencyRateTTL must be at least 60 seconds")
        }
        return errors.isEmpty ? .valid : .invalid(errors)
    }

    func provideActions(
        query: String, scoring: ScoringContext
    ) async -> [any Action] {
        let trimmed = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return [] }

        if let cache = rateCache {
            await cache.fetchIfNeeded()
        }

        let rates = await rateCache?.cachedRates
        let results = MathParser.parse(trimmed, currencyRates: rates)
        guard !results.isEmpty else { return [] }

        let cfg = config
        var actions: [MathAction] = results.compactMap { result in
            buildAction(for: result, query: trimmed, config: cfg)
        }

        if let enabled = cfg.enabledActions {
            actions = actions.filter { action in
                enabled.contains(action.resultType.rawValue)
            }
        }

        return actions
    }

    // MARK: - Action Building

    private func buildAction(
        for result: MathParser.ParseResult,
        query: String,
        config: MathConfig
    ) -> MathAction? {
        switch result {
        case let .expression(expression, value):
            return buildExpressionAction(
                expression: expression, value: value,
                query: query, config: config
            )
        case let .unitConversion(value, fromUnit, fromUnitFull, toUnit, toUnitFull, converted, category):
            let conv = UnitConverter.ConversionResult(
                value: value, fromUnit: fromUnit,
                fromUnitFull: fromUnitFull, toUnit: toUnit,
                toUnitFull: toUnitFull, result: converted,
                category: category
            )
            return buildUnitAction(
                conv: conv, query: query, config: config
            )
        case let .currencyConversion(value, fromCurrency, toCurrency, converted):
            return buildCurrencyAction(
                value: value, fromCurrency: fromCurrency,
                toCurrency: toCurrency, converted: converted,
                query: query, config: config
            )
        case let .percentage(pctValue, ofValue, pctResult):
            return buildPercentageAction(
                pctValue: pctValue, ofValue: ofValue,
                result: pctResult, query: query, config: config
            )
        case let .baseConversion(original, fromBase, conversions):
            return buildBaseAction(
                original: original, fromBase: fromBase,
                conversions: conversions, query: query,
                config: config
            )
        }
    }

    private func buildExpressionAction(
        expression: String, value: Double,
        query: String, config: MathConfig
    ) -> MathAction {
        let formatted = MathParser.formatNumber(
            value, decimalPlaces: config.decimalPlaces
        )
        let isNonTrivial = ExpressionParser.isNonTrivial(expression)
        let copyOnSelect = config.copyOnSelect
        return MathAction(
            id: ActionID(module: "math", name: "expr.\(expression.hashValue)"),
            title: "= \(formatted)",
            subtitle: expression,
            iconName: "equal.circle",
            relevanceScore: isNonTrivial ? 0.98 : 0.85,
            keywords: [query.lowercased(), "math", "calculate"],
            resultType: .expression,
            formattedResult: formatted,
            detailLines: [
                (label: "Expression", value: expression),
                (label: "Result", value: formatted),
            ]
        ) { _ in
            if copyOnSelect {
                await MainActor.run {
                    ClipboardManager.writeToPasteboard(formatted)
                }
            }
            return .dismiss
        }
    }

    private func buildUnitAction(
        conv: UnitConverter.ConversionResult,
        query: String, config: MathConfig
    ) -> MathAction {
        let dp = config.decimalPlaces
        let copyOnSelect = config.copyOnSelect
        let formattedResult = MathParser.formatNumber(conv.result, decimalPlaces: dp)
        let formattedValue = MathParser.formatNumber(conv.value, decimalPlaces: dp)
        let fromUnit = conv.fromUnit
        let toUnit = conv.toUnit
        return MathAction(
            id: ActionID(module: "math", name: "unit.\(query.hashValue)"),
            title: "= \(formattedResult) \(toUnit)",
            subtitle: "\(formattedValue) \(fromUnit) \u{2192} \(toUnit)",
            iconName: "arrow.left.arrow.right",
            relevanceScore: 0.98,
            keywords: [query.lowercased(), "convert", "unit", conv.category.lowercased()],
            resultType: .unitConversion,
            formattedResult: "\(formattedResult) \(toUnit)",
            detailLines: [
                (label: "From", value: "\(formattedValue) \(conv.fromUnitFull)"),
                (label: "To", value: "\(formattedResult) \(conv.toUnitFull)"),
                (label: "Category", value: conv.category),
            ]
        ) { _ in
            if copyOnSelect {
                await MainActor.run {
                    ClipboardManager.writeToPasteboard(formattedResult)
                }
            }
            return .dismiss
        }
    }

    private func buildCurrencyAction(
        value: Double, fromCurrency: String,
        toCurrency: String, converted: Double,
        query: String, config: MathConfig
    ) -> MathAction {
        let copyOnSelect = config.copyOnSelect
        let formattedResult = MathParser.formatNumber(converted, decimalPlaces: 2)
        let formattedValue = MathParser.formatNumber(value, decimalPlaces: 2)
        let rate = converted / value
        let formattedRate = MathParser.formatNumber(rate, decimalPlaces: 4)
        return MathAction(
            id: ActionID(module: "math", name: "currency.\(query.hashValue)"),
            title: "= \(formattedResult) \(toCurrency)",
            subtitle: "\(formattedValue) \(fromCurrency) \u{2192} \(toCurrency)",
            iconName: "dollarsign.circle",
            relevanceScore: 0.98,
            keywords: [query.lowercased(), "currency", "exchange",
                       fromCurrency.lowercased(), toCurrency.lowercased()],
            resultType: .currencyConversion,
            formattedResult: "\(formattedResult) \(toCurrency)",
            detailLines: [
                (label: "From", value: "\(formattedValue) \(fromCurrency)"),
                (label: "To", value: "\(formattedResult) \(toCurrency)"),
                (label: "Rate", value: "1 \(fromCurrency) = \(formattedRate) \(toCurrency)"),
            ]
        ) { _ in
            if copyOnSelect {
                await MainActor.run {
                    ClipboardManager.writeToPasteboard(formattedResult)
                }
            }
            return .dismiss
        }
    }

    private func buildPercentageAction(
        pctValue: Double, ofValue: Double, result: Double,
        query: String, config: MathConfig
    ) -> MathAction {
        let dp = config.decimalPlaces
        let copyOnSelect = config.copyOnSelect
        let formatted = MathParser.formatNumber(result, decimalPlaces: dp)
        let pctStr = MathParser.formatNumber(pctValue, decimalPlaces: dp)
        let ofStr = MathParser.formatNumber(ofValue, decimalPlaces: dp)
        return MathAction(
            id: ActionID(module: "math", name: "percent.\(query.hashValue)"),
            title: "= \(formatted)",
            subtitle: "\(pctStr)% of \(ofStr)",
            iconName: "percent",
            relevanceScore: 0.98,
            keywords: [query.lowercased(), "percent", "percentage"],
            resultType: .percentage,
            formattedResult: formatted,
            detailLines: [
                (label: "Percentage", value: "\(pctStr)%"),
                (label: "Of", value: ofStr),
                (label: "Result", value: formatted),
            ]
        ) { _ in
            if copyOnSelect {
                await MainActor.run {
                    ClipboardManager.writeToPasteboard(formatted)
                }
            }
            return .dismiss
        }
    }

    private func buildBaseAction(
        original: String, fromBase: String,
        conversions: [(base: String, value: String)],
        query: String, config: MathConfig
    ) -> MathAction {
        let copyOnSelect = config.copyOnSelect
        let primaryResult = conversions.first?.value ?? original
        return MathAction(
            id: ActionID(module: "math", name: "base.\(query.hashValue)"),
            title: conversions.map(\.value).joined(separator: "  "),
            subtitle: "\(original) (\(fromBase))",
            iconName: "number",
            relevanceScore: 0.96,
            keywords: [query.lowercased(), "hex", "binary", "octal",
                       "decimal", "base", "convert"],
            resultType: .baseConversion,
            formattedResult: primaryResult,
            detailLines: conversions.map { (label: $0.base, value: $0.value) }
        ) { _ in
            if copyOnSelect {
                await MainActor.run {
                    ClipboardManager.writeToPasteboard(primaryResult)
                }
            }
            return .dismiss
        }
    }
}
