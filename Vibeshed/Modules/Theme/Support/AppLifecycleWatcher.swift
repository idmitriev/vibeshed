import AppKit

/// Calls back whenever an app with the given bundle ID launches or quits.
@MainActor
final class AppLifecycleWatcher {
    enum Event {
        case launch
        case terminate

        var notification: Notification.Name {
            switch self {
            case .launch: NSWorkspace.didLaunchApplicationNotification
            case .terminate: NSWorkspace.didTerminateApplicationNotification
            }
        }
    }

    private var observer: NSObjectProtocol?

    init(bundleID: String, on event: Event, handler: @escaping @Sendable () -> Void) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: event.notification, object: nil, queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == bundleID { handler() }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
