import AppKit
import os

final class FocusedAppTracker: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var _bundleID: String = ""

    /// Thread-safe read of the currently focused app's bundle ID.
    /// Called from the event tap thread.
    var focusedBundleID: String {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _bundleID
    }

    /// Must be called from MainActor to start observing workspace notifications.
    @MainActor
    func start() {
        let initial = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        os_unfair_lock_lock(&lock)
        _bundleID = initial
        os_unfair_lock_unlock(&lock)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        Log.keybindings.debug("FocusedAppTracker started (initial: \(initial, privacy: .public))")
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier
        else { return }
        os_unfair_lock_lock(&lock)
        _bundleID = bundleID
        os_unfair_lock_unlock(&lock)
    }
}
