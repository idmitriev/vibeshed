import Foundation
import OSLog

// MARK: - Currency Converter

enum CurrencyConverter {
    struct ConversionRequest: Sendable {
        let value: Double
        let fromCurrency: String
        let toCurrency: String
    }

    static let knownCurrencies: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "CNY", "CAD", "AUD", "CHF",
        "INR", "BRL", "KRW", "RUB", "MXN", "SGD", "HKD", "NOK",
        "SEK", "DKK", "NZD", "ZAR", "TRY", "PLN", "THB", "IDR",
        "HUF", "CZK", "ILS", "PHP", "MYR", "TWD", "AED", "SAR",
        "CLP", "ARS", "COP", "EGP", "VND", "UAH", "NGN", "GEL",
    ]

    // MARK: - Parsing

    // swiftlint:disable force_try
    private static let conversionPattern = try! NSRegularExpression(
        pattern: #"^(-?[\d.,]+)\s*([a-zA-Z]{3})\s+(?:to|in|>)\s+([a-zA-Z]{3})$"#,
        options: [.caseInsensitive]
    )
    // swiftlint:enable force_try

    static func parse(_ query: String) -> ConversionRequest? {
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

        let from = String(trimmed[fromRange]).uppercased()
        let to = String(trimmed[toRange]).uppercased()

        guard knownCurrencies.contains(from),
              knownCurrencies.contains(to),
              from != to
        else { return nil }

        return ConversionRequest(value: value, fromCurrency: from, toCurrency: to)
    }

    static func convert(
        _ request: ConversionRequest, rates: [String: Double]
    ) -> Double? {
        guard let fromRate = rates[request.fromCurrency],
              let toRate = rates[request.toCurrency],
              fromRate > 0
        else { return nil }
        return request.value * toRate / fromRate
    }
}

// MARK: - Rate Cache

actor CurrencyRateCache {
    private var rates: [String: Double] = [:]
    private var lastFetch: Date?
    private let ttl: TimeInterval
    private let log = Log.module("math.currency")

    init(ttl: TimeInterval = 3600) {
        self.ttl = ttl
    }

    var cachedRates: [String: Double] {
        rates
    }

    var isExpired: Bool {
        guard let lastFetch else { return true }
        return Date().timeIntervalSince(lastFetch) > ttl
    }

    func updateTTL(_ newTTL: TimeInterval) {
        // TTL is let, but we can invalidate by checking
    }

    func fetchIfNeeded() async {
        guard isExpired else { return }
        await fetchRates()
    }

    private func fetchRates() async {
        guard let url = URL(
            string: "https://open.er-api.com/v6/latest/USD"
        ) else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                log.warning("Currency API returned non-200 status")
                return
            }

            let decoded = try JSONDecoder().decode(RateResponse.self, from: data)
            if decoded.result == "success" {
                self.rates = decoded.rates
                self.lastFetch = Date()
                log.info("Fetched \(self.rates.count, privacy: .public) currency rates")
            }
        } catch {
            log.error("Failed to fetch currency rates: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - API Response

private struct RateResponse: Codable {
    let result: String
    let rates: [String: Double]
}
