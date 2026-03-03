import Foundation

struct LayoutCorrectionHint: Equatable, Sendable {
    let originalQuery: String
    let correctedQuery: String
    let sourceLayoutName: String
}
