import AppKit

/// macOS security and consent dialogs. While one is up, a take stops instead
/// of sending input: a synthesized Return would answer it.
@MainActor
enum SystemDialogs {
    /// Owners of the dialogs seen so far: screen recording / accessibility
    /// confirmations (universalAccessAuthWarn), consent alerts
    /// (UserNotificationCenter), password prompts (SecurityAgent) and
    /// Gatekeeper's first-launch check (CoreServicesUIAgent).
    static let owners: Set<String> = [
        "universalAccessAuthWarn", "UserNotificationCenter", "SecurityAgent", "CoreServicesUIAgent",
    ]

    static func current() -> WindowInfo? {
        WindowInfo.onScreen().first { owners.contains($0.owner) && $0.frame.width > 50 }
    }

    /// Notification banners and notification permission requests: Notification Center
    /// shows them in a full-screen window above apps (its widgets sit below the desktop).
    /// Some stay up until clicked or until there's user activity again.
    static func banner() -> WindowInfo? {
        WindowInfo.onScreen().first { $0.owner == "Notification Center" && $0.layer >= 0 }
    }

    static func ensureNone() throws {
        guard let dialog = current() else { return }
        let title = dialog.title.isEmpty ? "" : " “\(dialog.title)”"
        throw AgentError(
            "macOS is showing a \(dialog.owner) dialog\(title) in the VM — answer it there and run again "
                + "(no input was sent while it was up)"
        )
    }
}
