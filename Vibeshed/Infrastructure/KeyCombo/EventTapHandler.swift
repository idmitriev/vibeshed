import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

final class EventTapHandler: @unchecked Sendable {
    private let executor: @Sendable (ActionID) -> Void
    private let focusedAppTracker: FocusedAppTracker

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?
    private var retainedSelf: Unmanaged<EventTapHandler>?

    // Binding tables — guarded by lock
    private var lock = os_unfair_lock()
    private var tables = BindingTables()

    /// Apps that opt out of every binding and remap. Owns its own lock.
    private let exclusions = AppExclusionList()

    /// Feeds the keystroke visualizer. Owns its own lock.
    private let keystrokes = KeystrokeReporter()

    // Modifier hold state — only accessed from tap callback thread
    private var spaceHeld = false
    private var spaceUsedAsModifier = false
    private var tabHeld = false
    private var tabUsedAsModifier = false

    init(
        focusedAppTracker: FocusedAppTracker,
        executor: @escaping @Sendable (ActionID) -> Void
    ) {
        self.focusedAppTracker = focusedAppTracker
        self.executor = executor
    }

    deinit {
        stop()
    }

    // MARK: - Public

    /// Attempts to start the CGEvent tap. Returns `true` on success.
    @discardableResult
    func start() -> Bool {
        guard tapPort == nil else { return true }

        let eventMask: CGEventMask =
            ((1 << CGEventType.keyDown.rawValue)
                    | (1 << CGEventType.keyUp.rawValue)
                    | (1 << CGEventType.flagsChanged.rawValue)
                    | (1 << CGEventType.otherMouseDown.rawValue)
                    | (1 << CGEventType.otherMouseUp.rawValue))

        // `self` is passed as userInfo to the C callback; balance with release() in stop()
        let unmanaged = Unmanaged.passRetained(self)

        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: eventTapCallback,
                userInfo: unmanaged.toOpaque()
            )
        else {
            unmanaged.release()
            Log.keybindings.error(
                "Failed to create CGEventTap — grant Accessibility permission"
            )
            Log.stderr("  ✗ event tap: CGEvent.tapCreate failed — Accessibility permission not granted")
            return false
        }

        retainedSelf = unmanaged

        tapPort = port

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source

        let tapThread = Thread { [weak self] in
            guard let self, let source else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        tapThread.name = "com.ivandmitriev.Vibeshed.eventtap"
        tapThread.qualityOfService = .userInteractive
        tapThread.start()
        thread = tapThread

        Log.keybindings.info("Event tap started (thread: \(tapThread.name ?? "unnamed", privacy: .public))")
        Log.stderr("  ✓ event tap: created and running on dedicated thread")
        return true
    }

    func stop() {
        if let runLoop = tapRunLoop {
            CFRunLoopStop(runLoop)
        }
        if let port = tapPort {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source = runLoopSource, let runLoop = tapRunLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        // Release the retained self that was passed to tapCreate
        retainedSelf?.release()
        retainedSelf = nil
        tapPort = nil
        runLoopSource = nil
        tapRunLoop = nil
        thread = nil

        Log.keybindings.info("Event tap stopped")
    }

    func updateBindings(_ resolved: ResolvedBindingSet, excluded: Set<String> = []) {
        let newTables = BindingTables(resolved)
        Log.keybindings.debug("Bindings: \(newTables.summary, privacy: .public)")

        exclusions.update(excluded)

        os_unfair_lock_lock(&lock)
        tables = newTables
        os_unfair_lock_unlock(&lock)
    }

    func setKeystrokeSink(_ sink: (@Sendable (KeystrokeEvent) -> Void)?) {
        keystrokes.setSink(sink)
    }

    // MARK: - Lookup Helpers (called from tap callback thread)

    /// The tables as of now, for one event's lookups. Copying is cheap (the
    /// dictionaries are copy-on-write) and keeps the lock hold to a single read.
    private func currentTables() -> BindingTables {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return tables
    }

    private static let relevantModifiers: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    private func maskedFlags(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(Self.relevantModifiers)
    }
}

// MARK: - Event Handling (tap callback thread)

extension EventTapHandler {
    fileprivate func handleEvent(
        proxy _: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enabling a disabled tap has to happen whatever app is focused,
        // so it is checked before the exclusion bypass below.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port = tapPort {
                let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
                Log.keybindings.warning(
                    "Event tap disabled by \(reason, privacy: .public), re-enabling"
                )
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if exclusions.excludes(focusedAppTracker.focusedBundleIDLowercased) {
            // Hands off entirely: no bindings, no remaps, no capslock/space/tab
            // interception. Clear any half-finished modifier hold so the next
            // non-excluded app doesn't inherit stale state.
            spaceHeld = false
            tabHeld = false
            if type == .keyDown, !isInjected(event) {
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                keystrokes.reportKeyDown(event, keyCode: keyCode, outcome: .passedThrough)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event: event)

        case .keyDown:
            return handleKeyDown(event: event)

        case .keyUp:
            return handleKeyUp(event: event)

        case .otherMouseDown:
            return handleMouseDown(event: event)

        case .otherMouseUp:
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        // CapsLock state is tracked via IOKit HID (CapsLockMonitor).
        // Suppress the capslock flagsChanged event when we have
        // capslock bindings to prevent the LED toggle.
        if !currentTables().capsLock.isEmpty {
            let keyCode = UInt16(
                event.getIntegerValueField(.keyboardEventKeycode)
            )
            if keyCode == UInt16(kVK_CapsLock) {
                return nil // Suppress LED toggle
            }
            // Also strip alphaShift from other modifier events
            // so held capslock doesn't affect letter case.
            if event.flags.contains(.maskAlphaShift) {
                event.flags = event.flags.subtracting(.maskAlphaShift)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Pass through events we injected ourselves (e.g. mouse remaps)
        if isInjected(event) {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Read focused app and tables once for all lookups in this event
        let focusedApp = focusedAppTracker.focusedBundleID
        let tables = currentTables()

        // Strip alphaShift so held capslock doesn't uppercase letters
        if !tables.capsLock.isEmpty, event.flags.contains(.maskAlphaShift) {
            event.flags = event.flags.subtracting(.maskAlphaShift)
        }

        if beginModifierHold(keyCode: keyCode, tables: tables) {
            return nil // Suppress space/tab until we know if it's a modifier
        }
        if handleModifierCombo(event: event, keyCode: keyCode, focusedApp: focusedApp, tables: tables) {
            return nil
        }
        return handleStandardCombo(event: event, keyCode: keyCode, focusedApp: focusedApp, tables: tables)
    }

    /// Space or Tab pressed while something is bound behind it: start holding it as a
    /// modifier. True when the key press should be suppressed until release.
    private func beginModifierHold(keyCode: UInt16, tables: BindingTables) -> Bool {
        if keyCode == Self.spaceKeyCode, !spaceHeld, !tables.space.isEmpty {
            spaceHeld = true
            spaceUsedAsModifier = false
            return true
        }
        if keyCode == Self.tabKeyCode, !tabHeld, !tables.tab.isEmpty || !tables.tabRemaps.isEmpty {
            tabHeld = true
            tabUsedAsModifier = false
            return true
        }
        return false
    }

    /// CapsLock / Space / Tab + key combos. True when the key press was consumed.
    private func handleModifierCombo(
        event: CGEvent,
        keyCode: UInt16,
        focusedApp: String,
        tables: BindingTables
    ) -> Bool {
        // Caps-lock modifier combos (state from IOKit HID)
        if CapsLockMonitor.shared.isPressed,
           let actionID = tables.capsLock[keyCode]?.resolve(focusedApp: focusedApp)
        {
            Log.keybindings.info(
                "CapsLock+\(keyCode, privacy: .public) → \(actionID.rawValue, privacy: .public)"
            )
            keystrokes.reportKeyDown(event, keyCode: keyCode, heldKey: .capsLock, outcome: .binding(actionID))
            executor(actionID)
            return true
        }

        // Space modifier combos
        if spaceHeld, keyCode != Self.spaceKeyCode,
           let actionID = tables.space[keyCode]?.resolve(focusedApp: focusedApp)
        {
            spaceUsedAsModifier = true
            Log.keybindings.info(
                "Space+\(keyCode, privacy: .public) → \(actionID.rawValue, privacy: .public)"
            )
            keystrokes.reportKeyDown(event, keyCode: keyCode, heldKey: .space, outcome: .binding(actionID))
            executor(actionID)
            return true
        }

        // Tab modifier combos — check remaps first, then bindings
        guard tabHeld, keyCode != Self.tabKeyCode else { return false }
        if let remap = tables.tabRemaps[keyCode]?[focusedApp] ?? tables.tabRemaps[keyCode]?[""] {
            tabUsedAsModifier = true
            keystrokes.reportKeyDown(event, keyCode: keyCode, heldKey: .tab, outcome: .remap(remap))
            injectKeyPress(keyCode: remap.keyCode, modifiers: remap.modifiers)
            return true
        }
        if let actionID = tables.tab[keyCode]?.resolve(focusedApp: focusedApp) {
            tabUsedAsModifier = true
            Log.keybindings.info(
                "Tab+\(keyCode, privacy: .public) → \(actionID.rawValue, privacy: .public)"
            )
            keystrokes.reportKeyDown(event, keyCode: keyCode, heldKey: .tab, outcome: .binding(actionID))
            executor(actionID)
            return true
        }
        return false
    }

    /// Standard modifier+key combos — remaps first, then bindings.
    private func handleStandardCombo(
        event: CGEvent,
        keyCode: UInt16,
        focusedApp: String,
        tables: BindingTables
    ) -> Unmanaged<CGEvent>? {
        let flags = maskedFlags(event.flags)
        let key = StandardKey(keyCode: keyCode, modifiers: flags)

        // Remap: modify the event in-place and pass it through. (Integer interpolations
        // in these log lines are public by default in os_log.)
        if let remap = tables.standardRemaps[key]?[focusedApp] ?? tables.standardRemaps[key]?[""] {
            Log.keybindings.info(
                "Remap key=\(keyCode) → key=\(remap.keyCode) [\(focusedApp, privacy: .public)]"
            )
            keystrokes.reportKeyDown(event, keyCode: keyCode, outcome: .remap(remap))
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(remap.keyCode))
            // Set target modifiers, preserving non-relevant flags (e.g. alphaShift)
            let preserved = event.flags.subtracting(Self.relevantModifiers)
            event.flags = remap.modifiers.union(preserved)
            return Unmanaged.passUnretained(event)
        }

        // Action binding
        if let actionID = tables.standard[key]?.resolve(focusedApp: focusedApp) {
            Log.keybindings.info(
                "Key \(keyCode) flags=\(flags.rawValue) → \(actionID.rawValue, privacy: .public)"
            )
            keystrokes.reportKeyDown(event, keyCode: keyCode, outcome: .binding(actionID))
            executor(actionID)
            return nil
        }

        keystrokes.reportKeyDown(event, keyCode: keyCode, outcome: .passedThrough)

        // Log unmatched events when modifiers are held (skip plain typing)
        if flags.rawValue != 0 {
            Log.keybindings.debug(
                "Unmatched keyDown: key=\(keyCode) flags=\(flags.rawValue) (\(tables.standard.count) bindings)"
            )
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Pass through events we injected ourselves
        if isInjected(event) {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Strip alphaShift so held capslock doesn't uppercase letters
        if !currentTables().capsLock.isEmpty, event.flags.contains(.maskAlphaShift) {
            event.flags = event.flags.subtracting(.maskAlphaShift)
        }

        // The replacement press injected below isn't reported by keyDown, so a plain tap is reported here.
        if keyCode == Self.spaceKeyCode, spaceHeld {
            spaceHeld = false
            if !spaceUsedAsModifier {
                // Space was tapped, not used as modifier — inject space keypress
                keystrokes.reportTap(keyCode: keyCode, characters: " ")
                injectKeyPress(keyCode: Self.spaceKeyCode, modifiers: [])
            }
            return nil
        }

        if keyCode == Self.tabKeyCode, tabHeld {
            tabHeld = false
            if !tabUsedAsModifier {
                // Tab was tapped, not used as modifier — inject tab keypress
                keystrokes.reportTap(keyCode: keyCode, characters: "\t")
                injectKeyPress(keyCode: Self.tabKeyCode, modifiers: [])
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleMouseDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let flags = maskedFlags(event.flags)
        let focusedApp = focusedAppTracker.focusedBundleID
        let mouseKey = MouseKey(button: button, modifiers: flags)
        let flagBits = flags.rawValue

        let tables = currentTables()

        // Mouse remaps take priority — inject key event instead
        if let remap = tables.mouseRemaps[mouseKey] {
            Log.keybindings.info(
                "MouseRemap btn=\(button, privacy: .public) → key=\(remap.keyCode, privacy: .public)"
            )
            keystrokes.reportMouse(button: button, modifiers: flags, outcome: .remap(remap))
            injectKeyPress(keyCode: remap.keyCode, modifiers: remap.modifiers)
            return nil
        }

        if let actionID = tables.mouse[mouseKey]?.resolve(focusedApp: focusedApp) {
            // Integer interpolations are public by default in os_log.
            Log.keybindings.info(
                "Mouse \(button) flags=\(flagBits) → \(actionID.rawValue, privacy: .public)"
            )
            keystrokes.reportMouse(button: button, modifiers: flags, outcome: .binding(actionID))
            executor(actionID)
            return nil
        }

        Log.keybindings.debug(
            "Unmatched mouseDown: button=\(button, privacy: .public) flags=\(flagBits, privacy: .public)"
        )

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Helpers

    /// Marker value set on `eventSourceUserData` so the tap recognises
    /// injected events and passes them through untouched.
    private static let injectedMarker: Int64 = 0x5649_4245 // "VIBE"

    private static let spaceKeyCode = UInt16(kVK_Space)
    private static let tabKeyCode = UInt16(kVK_Tab)

    private func isInjected(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.injectedMarker
    }

    private func injectKeyPress(keyCode: UInt16, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        {
            down.flags = modifiers
            up.flags = modifiers
            down.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
            up.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }
}

// MARK: - C Callback

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let handler = Unmanaged<EventTapHandler>.fromOpaque(userInfo).takeUnretainedValue()
    return handler.handleEvent(proxy: proxy, type: type, event: event)
}
