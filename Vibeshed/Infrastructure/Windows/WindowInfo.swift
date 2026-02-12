import CoreGraphics

struct WindowInfo: Sendable, Identifiable, Equatable {
    let id: Int
    let title: String
    let appName: String
    let bundleID: String?
    let pid: pid_t
    let frame: CGRect
    let screenFrame: CGRect
    let isOnScreen: Bool
    let isMinimized: Bool

    var displayLabel: String {
        if title.isEmpty {
            return appName
        }
        return "\(appName) — \(title)"
    }
}
