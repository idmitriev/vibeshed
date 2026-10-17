import Foundation

/// A row in the picker's list: the UI-facing value for an `Action`.
struct ActionItem: Identifiable, Equatable, Sendable {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconSystemName: String?
    /// Path to an app bundle whose Finder icon represents this item (apps/windows).
    let appIconPath: String?
    let score: Double
    let moduleID: String
    let hasParameters: Bool
    let keywords: [String]
    var titleHighlightRanges: [Range<String.Index>]?

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconSystemName: String? = nil,
        appIconPath: String? = nil,
        score: Double = 0,
        moduleID: String = "",
        hasParameters: Bool = false,
        keywords: [String] = [],
        titleHighlightRanges: [Range<String.Index>]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.appIconPath = appIconPath
        self.score = score
        self.moduleID = moduleID
        self.hasParameters = hasParameters
        self.keywords = keywords
        self.titleHighlightRanges = titleHighlightRanges
    }
}
