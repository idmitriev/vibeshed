import SwiftUI

struct ActionParameter: Sendable, Identifiable {
    let id: String
    let label: String
    let type: ParameterType
    let isRequired: Bool
    let defaultValue: String?
    /// For selections: the picker reports each highlighted option to the owning module
    /// (`Module.previewParameterOption`) so it can apply it live, and tells it whether
    /// the preview ended in a commit or a cancel (`endParameterPreview`).
    let livePreview: Bool
    /// For dynamic selections whose options already answer the query, like a web search's
    /// results: the picker lists them in the module's order instead of fuzzy-matching
    /// their labels against the query, which would drop hits whose titles don't contain it.
    let rankedByModule: Bool

    init(
        id: String,
        label: String,
        type: ParameterType,
        isRequired: Bool = false,
        defaultValue: String? = nil,
        livePreview: Bool = false,
        rankedByModule: Bool = false
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.livePreview = livePreview
        self.rankedByModule = rankedByModule
    }
}

enum ParameterType: Sendable {
    case text(placeholder: String?)
    case number(min: Double?, max: Double?)
    case toggle
    case selection([ParameterOption])
    case dynamicSelection(hint: String)
    case path(allowsDirectories: Bool)
}

struct ParameterOption: Sendable, Identifiable {
    let id: String
    let label: String
    let subtitle: String?
    let iconName: String?
    /// A file shows its Finder icon (an app bundle, say); a web URL is loaded as an image
    /// (a thumbnail).
    let iconURL: URL?
    /// Extra search terms, prefix-matched like action keywords (never shown).
    let keywords: [String]
    var labelHighlightRanges: [Range<String.Index>]?
    /// The value currently in effect (the active theme, the selected device, …): marked
    /// in the list and pre-selected when the list opens unfiltered.
    var isCurrent: Bool
    /// Small color chips drawn at the row's trailing edge.
    var swatches: [Color]
    /// Custom content for the preview panel while this option is highlighted.
    var makePreview: (@MainActor @Sendable () -> AnyView)?

    init(
        id: String,
        label: String,
        subtitle: String? = nil,
        iconName: String? = nil,
        iconURL: URL? = nil,
        keywords: [String] = [],
        isCurrent: Bool = false,
        swatches: [Color] = [],
        makePreview: (@MainActor @Sendable () -> AnyView)? = nil
    ) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.iconName = iconName
        self.iconURL = iconURL
        self.keywords = keywords
        self.isCurrent = isCurrent
        self.swatches = swatches
        self.makePreview = makePreview
    }
}

/// Exclude display-only decoration (highlight ranges, preview factory) from equality/hashing.
extension ParameterOption: Equatable {
    static func == (lhs: ParameterOption, rhs: ParameterOption) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.subtitle == rhs.subtitle
            && lhs.iconName == rhs.iconName && lhs.iconURL == rhs.iconURL
            && lhs.keywords == rhs.keywords && lhs.isCurrent == rhs.isCurrent && lhs.swatches == rhs.swatches
    }
}

extension ParameterOption: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(label)
        hasher.combine(subtitle)
        hasher.combine(iconName)
        hasher.combine(iconURL)
        hasher.combine(isCurrent)
    }
}
