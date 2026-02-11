import Foundation

struct AppInfo: Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let bundleURL: URL
    let isRunning: Bool
    let pid: pid_t?
    let windowCount: Int

    var displayLabel: String {
        if isRunning, windowCount > 0 {
            return "\(name) (\(windowCount) window\(windowCount == 1 ? "" : "s"))"
        }
        return name
    }
}
