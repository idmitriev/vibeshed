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
    case custom(name: String, payload: [String: String])
}
