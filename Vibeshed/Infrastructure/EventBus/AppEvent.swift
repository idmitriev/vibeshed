import Foundation

enum AppEvent: Sendable {
    case moduleRegistered(String)
    case moduleUnregistered(String)
    case configReloaded
    case permissionChanged(Permission, granted: Bool)
    case moduleActionsChanged(moduleID: String)
    case openURL(URL)
}
