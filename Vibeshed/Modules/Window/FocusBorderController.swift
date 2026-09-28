import AppKit
import ApplicationServices

/// Draws the focus border around the frontmost app's focused window — any window at least
/// `minimumSize` points wide and tall that doesn't cover its whole display — while
/// `window/toggleFocusBorder` has it on (runtime-only state, off at every launch).
///
/// Event-driven, so the border keeps up with focus: app activations and space switches,
/// the frontmost app's AX focused-window/moved/resized notifications, and global
/// left-mouse drags (the window server moves a window dragged by its title bar without
/// the app necessarily saying so). A `pollingInterval` poll backs these up for what
/// nothing announces: Mission Control, a closed last window, apps that post no AX
/// notifications.
///
/// A separate window can't track another app's live move or resize without visibly
/// lagging behind it, so the border doesn't try: the moment the bordered window's frame
/// starts changing it hides, and it comes back once the frame has held still for one
/// `settleCheckInterval` with the mouse button up.
@MainActor
final class FocusBorderController {
    static let shared = FocusBorderController()

    private(set) var isEnabled = false
    private var config = FocusBorderConfig()
    private var panel: FocusBorderPanel?

    /// The window the border currently surrounds; nil while it's hidden.
    private var shown: FocusedWindowSnapshot?
    /// Set while the bordered window moves or resizes; the border stays hidden meanwhile.
    private var settling: Settling?
    private var settleTask: Task<Void, Never>?

    private var observer: FocusedAppObserver?
    private var observedPID: pid_t?
    private var observerPending = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var dragMonitor: Any?
    private var pollTask: Task<Void, Never>?
    private var readInFlight = false
    private var readPending = false

    private static let settleCheckInterval: Duration = .milliseconds(40)

    private struct Settling {
        let window: FocusedWindowSnapshot
        /// Window-server bounds at the previous check (at the start, before the first).
        var lastBounds: CGRect?
        /// A move/resize notification arrived since the previous check.
        var changed = false
    }

    private init() {}

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            startWatching()
            refresh()
        } else {
            stopWatching()
            hide()
        }
    }

    /// Takes effect with the next refresh, which starts right away when the border is on.
    func configure(_ config: FocusBorderConfig) {
        self.config = config
        refresh()
    }

    /// From the frontmost app's AX observer (see `FocusedWindowReader.makeObserver`).
    func handleAXNotification(_ name: String, element: AXUIElement) {
        guard isEnabled else { return }
        switch name {
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            if let settling, CFEqual(settling.window.element, element) {
                self.settling?.changed = true
            } else if let shown, CFEqual(shown.element, element) {
                beginSettling(shown)
            }
        default:
            focusChanged()
        }
    }
}

// MARK: - Events

extension FocusBorderController {
    /// The focused window may have changed: re-aim the AX observer at the frontmost app,
    /// drop any settle in progress (the window it waits on may not be focused anymore),
    /// and re-read.
    private func focusChanged() {
        guard isEnabled else { return }
        observeFrontmostApp()
        endSettling()
        refresh()
    }

    /// A drag can move or resize the bordered window before its app posts a notification,
    /// or without one — the window server itself moves a window dragged by its title bar —
    /// so every drag event compares the window server's bounds with the bordered ones.
    private func mouseDragged() {
        guard isEnabled, settling == nil, let shown, let shownBounds = shown.liveBounds else { return }
        let bounds = WindowListHelper.onScreenBounds(of: shown.windowID)
        if bounds.map({ Self.roughlyEqual($0, shownBounds) }) != true {
            beginSettling(shown)
        }
    }
}

// MARK: - Refresh

extension FocusBorderController {
    /// Reads the focused window (off the main thread) and shows, moves, or hides the border
    /// to match. One read at a time: calls made meanwhile collapse into a single re-read.
    private func refresh() {
        guard isEnabled, settling == nil else { return }
        guard !readInFlight else {
            readPending = true
            return
        }
        guard let pid = Self.frontmostPID() else {
            hide()
            return
        }
        readInFlight = true
        Task { [weak self] in
            let window = await FocusedWindowReader.focusedWindow(of: pid)
            guard let self else { return }
            readInFlight = false
            apply(window)
            if readPending {
                readPending = false
                refresh()
            }
        }
    }

    private func apply(_ window: FocusedWindowSnapshot?) {
        guard isEnabled, settling == nil else { return }
        guard let window, qualifies(window) else {
            hide()
            return
        }
        let inPlace = window.liveBounds.map { Self.roughlyEqual($0, window.frame, tolerance: 2) } ?? false
        if let shown, shown.windowID == window.windowID,
           !inPlace || !Self.roughlyEqual(shown.frame, window.frame)
        {
            // The bordered window moved or resized and no event said so: an app that posts
            // no AX notifications, or a drag the poll noticed first.
            beginSettling(shown)
        } else if inPlace {
            show(window)
        } else {
            // On screen, but not where AX says: Mission Control or App Exposé has scattered
            // it to a thumbnail, and its frame means nothing there.
            hide()
        }
    }

    /// Whether `window` gets a border: on screen, at least `minimumSize` wide and tall, and
    /// not covering its whole display. A native full-screen window (or one sized to fill
    /// the display) has no room around it, and the border would spill onto a neighbouring
    /// display.
    private func qualifies(_ window: FocusedWindowSnapshot) -> Bool {
        guard window.liveBounds != nil,
              window.frame.width >= config.minimumSize,
              window.frame.height >= config.minimumSize
        else {
            return false
        }
        guard let screen = WindowListHelper.screen(forFrame: window.frame) else { return true }
        return !window.frame.insetBy(dx: -1, dy: -1).contains(WindowSizing.frameCG(of: screen))
    }

    /// The frontmost app's pid, or nil when its windows get no border: Vibeshed itself, and
    /// the Dock, which is frontmost during Launchpad and other Dock-hosted full-screen UI.
    private static func frontmostPID() -> pid_t? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "com.apple.dock"
        else {
            return nil
        }
        return app.processIdentifier
    }

    private static func roughlyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: Double = 1) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}

// MARK: - Settling

extension FocusBorderController {
    /// Hides the border until the window's frame holds still (see `settleCheck`).
    private func beginSettling(_ window: FocusedWindowSnapshot) {
        hide()
        settling = Settling(window: window, lastBounds: WindowListHelper.onScreenBounds(of: window.windowID))
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.settleCheckInterval)
                guard let self, !Task.isCancelled else { return }
                if settleCheck() { return }
            }
        }
    }

    /// One check while settling. Settled — the border re-reads the window and shows again —
    /// when since the previous check (or the start) there was no move/resize notification
    /// and no change in the window server's bounds, and the left mouse button is up (a drag
    /// can pause without ending).
    private func settleCheck() -> Bool {
        guard var current = settling else { return true }
        let bounds = WindowListHelper.onScreenBounds(of: current.window.windowID)
        let still = !current.changed && bounds == current.lastBounds
            && !CGEventSource.buttonState(.combinedSessionState, button: .left)
        guard still else {
            current.lastBounds = bounds
            current.changed = false
            settling = current
            return false
        }
        endSettling()
        refresh()
        return true
    }

    private func endSettling() {
        settleTask?.cancel()
        settleTask = nil
        settling = nil
    }
}

// MARK: - Panel

extension FocusBorderController {
    private func show(_ window: FocusedWindowSnapshot) {
        let panel = panel ?? makePanel()
        panel.surround(
            window.frame,
            width: config.width,
            cornerRadius: config.cornerRadius,
            color: Self.accentColor
        )
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        shown = window
    }

    private func hide() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        }
        shown = nil
    }

    private func makePanel() -> FocusBorderPanel {
        let panel = FocusBorderPanel()
        self.panel = panel
        return panel
    }

    /// The active theme's accent (the system accent without a theme), re-read on every
    /// show, so theme switches and live previews retint the border by the next poll.
    private static var accentColor: CGColor {
        ActiveTheme.shared.displayed?.palette.accent.cgColor ?? NSColor.controlAccentColor.cgColor
    }
}

// MARK: - Event Sources

extension FocusBorderController {
    private func startWatching() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification]
        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.focusChanged() }
            }
        }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.config.pollingInterval ?? 1))
                guard let self, !Task.isCancelled else { return }
                observeFrontmostApp()
                refresh()
            }
        }
        observeFrontmostApp()
    }

    private func stopWatching() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers = []
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
        }
        dragMonitor = nil
        pollTask?.cancel()
        pollTask = nil
        endSettling()
        stopObserving()
        readPending = false
    }

    /// Points the AX observer at the frontmost app, the only one whose window can have the
    /// border. Registering takes round trips to the app, so the observer is made off the
    /// main thread. An app too busy to answer (one still launching, often) gets none, and
    /// the poll calls this again until it does.
    private func observeFrontmostApp() {
        let pid = Self.frontmostPID()
        if pid != observedPID {
            stopObserving()
            observedPID = pid
        }
        guard let pid, observer == nil, !observerPending else { return }
        observerPending = true
        Task { [weak self] in
            let made = await FocusedWindowReader.makeObserver(for: pid)
            guard let self else { return }
            observerPending = false
            guard isEnabled else { return }
            if observedPID != pid {
                // The frontmost app changed while this one's observer was being made.
                observeFrontmostApp()
            } else if let made, observer == nil {
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made.observer), .commonModes)
                observer = made
            }
        }
    }

    private func stopObserving() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer.observer), .commonModes)
        }
        observer = nil
        observedPID = nil
    }
}
