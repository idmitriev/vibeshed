import ApplicationServices
import CoreGraphics

/// The frontmost app's focused window as the focus border sees it. An immutable CF
/// reference plus plain values, so it's safe to hand from the reader's queue to the main
/// actor (the AX API is thread-safe).
struct FocusedWindowSnapshot: @unchecked Sendable {
    let element: AXUIElement
    let windowID: CGWindowID
    /// AX frame, CG top-left-origin.
    let frame: CGRect
    /// Where the window server has the window right now; nil when it isn't on screen.
    let liveBounds: CGRect?
}

/// An AX observer created on the reader's queue; the main actor owns it from then on.
struct FocusedAppObserver: @unchecked Sendable {
    let observer: AXObserver
}

/// The focus border's Accessibility calls. Each one is a synchronous round trip serviced
/// on the target app's main thread, so — as in `MenuBarReader` — they run on private
/// serial queues with a short per-element timeout: a hung frontmost app can't stall
/// Vibeshed's main thread, and holds up the next read for at most `messagingTimeout`.
/// Observers are registered on a queue of their own, so registering never delays a read.
enum FocusedWindowReader {
    private static let readQueue = DispatchQueue(
        label: "com.ivandmitriev.Vibeshed.focusborder.read",
        qos: .userInteractive
    )
    private static let observerQueue = DispatchQueue(
        label: "com.ivandmitriev.Vibeshed.focusborder.observer",
        qos: .userInitiated
    )
    private static let messagingTimeout: Float = 0.25

    /// Registered on the application element, which covers every window of the app; the
    /// callback's element is the window concerned.
    private static let notifications = [
        kAXFocusedWindowChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
    ]

    static func focusedWindow(of pid: pid_t) async -> FocusedWindowSnapshot? {
        await withCheckedContinuation { continuation in
            readQueue.async {
                continuation.resume(returning: readFocusedWindow(of: pid))
            }
        }
    }

    /// An observer for `pid`'s focused-window changes and window moves/resizes. Its
    /// notifications reach `FocusBorderController.handleAXNotification` once its run-loop
    /// source is added to the main run loop. nil when the app didn't answer in time — one
    /// still launching often doesn't — so the caller can try again later.
    static func makeObserver(for pid: pid_t) async -> FocusedAppObserver? {
        await withCheckedContinuation { continuation in
            observerQueue.async {
                continuation.resume(returning: createObserver(for: pid))
            }
        }
    }

    private static func readFocusedWindow(of pid: pid_t) -> FocusedWindowSnapshot? {
        guard let window = AXWindowHelper.focusedWindow(for: pid, messagingTimeout: messagingTimeout),
              let windowID = AXWindowHelper.windowID(for: window)
        else {
            return nil
        }
        return FocusedWindowSnapshot(
            element: window,
            windowID: windowID,
            frame: AXWindowHelper.frame(of: window),
            liveBounds: WindowListHelper.onScreenBounds(of: windowID)
        )
    }

    private static func createObserver(for pid: pid_t) -> FocusedAppObserver? {
        var observer: AXObserver?
        guard AXObserverCreate(pid, focusBorderAXCallback, &observer) == .success, let observer else {
            return nil
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        // Other errors mean the app doesn't offer that notification (the poll covers for
        // it); a timeout means it's busy and may take it next time.
        let busy = notifications.contains {
            AXObserverAddNotification(observer, app, $0 as CFString, nil) == .cannotComplete
        }
        return busy ? nil : FocusedAppObserver(observer: observer)
    }
}

/// The observer's `AXObserverCallback`. Its run-loop source is on the main run loop, so
/// this runs on the main thread.
private func focusBorderAXCallback(
    _: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _: UnsafeMutableRawPointer?
) {
    let name = notification as String
    // Already on the main thread, so handing the element to the main actor crosses none.
    nonisolated(unsafe) let element = element
    MainActor.assumeIsolated {
        FocusBorderController.shared.handleAXNotification(name, element: element)
    }
}
