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

struct ParameterOption: Sendable, Identifiable, Hashable {
    let id: String
    let label: String
    let iconName: String?

    init(id: String, label: String, iconName: String? = nil) {
        self.id = id
        self.label = label
        self.iconName = iconName
    }
}
