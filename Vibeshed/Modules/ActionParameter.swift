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

    init(
        id: String,
        label: String,
        type: ParameterType,
        isRequired: Bool = false,
        defaultValue: String? = nil,
        livePreview: Bool = false
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
        self.livePreview = livePreview
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
    let iconURL: URL?
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
        isCurrent: Bool = false,
        swatches: [Color] = [],
        makePreview: (@MainActor @Sendable () -> AnyView)? = nil
    ) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.iconName = iconName
        self.iconURL = iconURL
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
            && lhs.isCurrent == rhs.isCurrent && lhs.swatches == rhs.swatches
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
