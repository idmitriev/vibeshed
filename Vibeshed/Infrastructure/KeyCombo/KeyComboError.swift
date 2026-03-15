import Foundation

enum KeyComboError: Error, LocalizedError {
    case invalidCombo(String, reason: String)
    case unknownKey(String)
    case unknownModifier(String)
    case actionNotFound(ActionID)
    case permissionRequired(Set<Permission>)
    case duplicateBinding(String)
    case invalidRemap(from: String, to: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .invalidCombo(combo, reason):
            "Invalid combo '\(combo)': \(reason)"
        case let .unknownKey(key):
            "Unknown key '\(key)'"
        case let .unknownModifier(modifier):
            "Unknown modifier '\(modifier)'"
        case let .actionNotFound(actionID):
            "Action not found: \(actionID)"
        case let .permissionRequired(permissions):
            "Permissions required: \(permissions.map(\.rawValue).sorted().joined(separator: ", "))"
        case let .duplicateBinding(combo):
            "Duplicate binding for '\(combo)'"
        case let .invalidRemap(from, to, reason):
            "Invalid remap '\(from)' → '\(to)': \(reason)"
        }
    }
}
