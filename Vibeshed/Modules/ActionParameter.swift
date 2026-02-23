import Foundation

struct ActionParameter: Sendable, Identifiable {
    let id: String
    let label: String
    let type: ParameterType
    let isRequired: Bool
    let defaultValue: String?

    init(
        id: String,
        label: String,
        type: ParameterType,
        isRequired: Bool = false,
        defaultValue: String? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.isRequired = isRequired
        self.defaultValue = defaultValue
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

    init(id: String, label: String, subtitle: String? = nil, iconName: String? = nil, iconURL: URL? = nil) {
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.iconName = iconName
        self.iconURL = iconURL
    }
}

// Exclude labelHighlightRanges from equality/hashing (display-only decoration)
extension ParameterOption: Equatable {
    static func == (lhs: ParameterOption, rhs: ParameterOption) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.subtitle == rhs.subtitle
            && lhs.iconName == rhs.iconName && lhs.iconURL == rhs.iconURL
    }
}

extension ParameterOption: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(label)
        hasher.combine(subtitle)
        hasher.combine(iconName)
        hasher.combine(iconURL)
    }
}
