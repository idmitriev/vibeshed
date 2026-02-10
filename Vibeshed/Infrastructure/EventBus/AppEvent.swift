import Foundation

enum AppEvent: Sendable {
    case pickerShown
    case pickerHidden
    case queryChanged(String)
    case actionExecuted(ActionID, moduleID: String)
    case actionFailed(ActionID, message: String)
    case moduleRegistered(String)
    case moduleUnregistered(String)
    case configReloaded
    case moduleConfigError(moduleID: String, message: String)
    case permissionChanged(Permission, granted: Bool)
    case modulePermissionError(moduleID: String, missing: Set<Permission>)
    case keybindingError(combo: String, message: String)
    case custom(name: String, payload: [String: String])
}
