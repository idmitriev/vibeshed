import Foundation

enum Permission: String, Sendable, CaseIterable, Hashable, Codable {
    case accessibility
    case screenRecording
    case automation
    case inputMonitoring
    case fullDiskAccess
    case calendars

    var displayName: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .automation: "Automation"
        case .inputMonitoring: "Input Monitoring"
        case .fullDiskAccess: "Full Disk Access"
        case .calendars: "Calendars"
        }
    }

    var grantInstructions: String {
        switch self {
        case .accessibility:
            "Open System Settings > Privacy & Security > Accessibility, then add Vibeshed."
        case .screenRecording:
            "Open System Settings > Privacy & Security > Screen Recording, then enable Vibeshed."
        case .automation:
            "Open System Settings > Privacy & Security > Automation, then allow Vibeshed to control other apps."
        case .inputMonitoring:
            "Open System Settings > Privacy & Security > Input Monitoring, then enable Vibeshed."
        case .fullDiskAccess:
            "Open System Settings > Privacy & Security > Full Disk Access, then enable Vibeshed."
        case .calendars:
            "Open System Settings > Privacy & Security > Calendars, then enable Vibeshed."
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .automation:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        case .fullDiskAccess:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .calendars:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        }
    }
}
