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
            return "Invalid combo '\(combo)': \(reason)"
        case let .unknownKey(key):
            return "Unknown key '\(key)'"
        case let .unknownModifier(modifier):
            return "Unknown modifier '\(modifier)'"
        case let .actionNotFound(actionID):
            return "Action not found: \(actionID)"
        case let .permissionRequired(permissions):
            let names = permissions.map(\.rawValue).sorted().joined(separator: ", ")
            return "Permissions required: \(names)"
        case let .duplicateBinding(combo):
            return "Duplicate binding for '\(combo)'"
        case let .invalidRemap(from, to, reason):
            return "Invalid remap '\(from)' → '\(to)': \(reason)"
        }
    }
}
