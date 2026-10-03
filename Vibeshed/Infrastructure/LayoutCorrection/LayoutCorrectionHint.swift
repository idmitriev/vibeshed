import Foundation

struct LayoutCorrectionHint: Equatable, Sendable {
    let originalQuery: String
    let correctedQuery: String
    let sourceLayoutName: String
}

/// Supplies Latin readings for a query typed with the wrong input source.
@MainActor
protocol LayoutCorrecting: AnyObject {
    func corrections(for query: String) -> [LayoutCorrectionHint]
}

extension LayoutTransliterator: LayoutCorrecting {}
