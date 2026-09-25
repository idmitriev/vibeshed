import AppKit

/// Calls back whenever an app with the given bundle ID launches.
@MainActor
final class AppLaunchWatcher {
    private var observer: NSObjectProtocol?

    init(bundleID: String, onLaunch: @escaping @Sendable () -> Void) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == bundleID { onLaunch() }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
