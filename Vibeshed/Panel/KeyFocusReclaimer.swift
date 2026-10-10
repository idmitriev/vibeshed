import AppKit

/// Decides whether the picker, holding keyboard focus for Shift runs, takes it back
/// after losing it. It does when the user didn't cause the loss: their latest physical
/// click or key press went to Vibeshed, so an app an action launched or focused came
/// forward. A click or key press anywhere else (another window, the Dock, ⌘Tab) lets
/// the picker go.
@MainActor
final class KeyFocusReclaimer {
    /// Slack between an event's time in the HID system and the timestamp Vibeshed sees.
    private static let inputTolerance: TimeInterval = 0.1
    /// Reclaims allowed within `reclaimWindow` — more means something keeps taking
    /// focus right back, and fighting it would trap the user.
    private static let maxReclaims = 3
    private static let reclaimWindow: TimeInterval = 2

    private static let inputTypes: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    /// When Vibeshed last received a click or key press (`NSEvent.timestamp`, seconds of uptime).
    private var latestLocalInput: TimeInterval = 0
    private var recentReclaims: [TimeInterval] = []
    private nonisolated(unsafe) var monitor: Any?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Starts recording Vibeshed's own clicks and key presses.
    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                self?.recordLocalInput(at: event.timestamp)
            }
            return event
        }
    }

    func recordLocalInput(at timestamp: TimeInterval) {
        latestLocalInput = max(latestLocalInput, timestamp)
    }

    /// Whether to take focus back now, judged by the user's latest physical input anywhere.
    func shouldReclaim() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let sinceLatestInput = Self.inputTypes
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? .infinity
        let reclaim = shouldReclaim(latestPhysicalInput: now - sinceLatestInput, now: now)
        let sinceLocalInput = now - latestLocalInput
        Log.picker.debug("""
        Picker lost key focus. Last input \(sinceLatestInput, format: .fixed(precision: 2))s ago, \
        in Vibeshed \(sinceLocalInput, format: .fixed(precision: 2))s ago; reclaiming: \(reclaim)
        """)
        return reclaim
    }

    func shouldReclaim(latestPhysicalInput: TimeInterval, now: TimeInterval) -> Bool {
        guard latestPhysicalInput <= latestLocalInput + Self.inputTolerance else { return false }
        recentReclaims.removeAll { now - $0 > Self.reclaimWindow }
        guard recentReclaims.count < Self.maxReclaims else { return false }
        recentReclaims.append(now)
        return true
    }

    /// Forgets past reclaims, for the next time the picker holds focus.
    func reset() {
        recentReclaims = []
    }
}
