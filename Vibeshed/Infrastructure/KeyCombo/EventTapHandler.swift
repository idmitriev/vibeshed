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
    private var standardBindings: [StandardKey: BindingSlot] = [:]
    private var capsLockBindings: [UInt16: BindingSlot] = [:]
    private var spaceBindings: [UInt16: BindingSlot] = [:]
    private var mouseBindings: [MouseKey: BindingSlot] = [:]
    private var mouseRemaps: [MouseKey: RemapTarget] = [:]
    private var standardRemaps: [StandardKey: [String: RemapTarget]] = [:]

    // Modifier hold state — only accessed from tap callback thread
    private var spaceHeld = false
    private var spaceUsedAsModifier = false

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

    // MARK: - Internal Types

    private struct BindingSlot {
        var global: ActionID?
        var appSpecific: [String: ActionID] = [:]

        func resolve(focusedApp: String) -> ActionID? {
            appSpecific[focusedApp] ?? global
        }
    }

    private struct RemapTarget {
        let keyCode: UInt16
        let modifiers: CGEventFlags
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

    // swiftlint:disable:next function_body_length
    func updateBindings(
        standard: [ResolvedBinding],
        capsLock: [ResolvedBinding],
        space: [ResolvedBinding],
        mouse: [ResolvedBinding],
        remaps: [ResolvedRemap],
        mouseRemapList: [ResolvedMouseRemap] = []
    ) {
        var newStandard: [StandardKey: BindingSlot] = [:]
        for binding in standard {
            if case .standard(let keyCode, let modifiers) = binding.comboType {
                let key = StandardKey(keyCode: keyCode, modifiers: modifiers)
                var slot = newStandard[key] ?? BindingSlot()
                if let app = binding.app {
                    slot.appSpecific[app] = binding.actionID
                } else {
                    slot.global = binding.actionID
                }
                newStandard[key] = slot
                let action = binding.actionID.rawValue
                let fl = modifiers.rawValue
                let scope = binding.app ?? "global"
                Log.keybindings.debug(
                    "  std key=\(keyCode, privacy: .public) fl=\(fl, privacy: .public) → \(action, privacy: .public) [\(scope, privacy: .public)]"
                )
            }
        }

        var newCapsLock: [UInt16: BindingSlot] = [:]
        for binding in capsLock {
            if case .capsLockModifier(let keyCode) = binding.comboType {
                var slot = newCapsLock[keyCode] ?? BindingSlot()
                if let app = binding.app {
                    slot.appSpecific[app] = binding.actionID
                } else {
                    slot.global = binding.actionID
                }
                newCapsLock[keyCode] = slot
                let action = binding.actionID.rawValue
                let combo = binding.rawCombo
                Log.keybindings.debug(
                    "  capslock key=\(keyCode, privacy: .public) → \(action, privacy: .public) (\(combo, privacy: .public))"
                )
            }
        }

        var newSpace: [UInt16: BindingSlot] = [:]
        for binding in space {
            if case .spaceModifier(let keyCode) = binding.comboType {
                var slot = newSpace[keyCode] ?? BindingSlot()
                if let app = binding.app {
                    slot.appSpecific[app] = binding.actionID
                } else {
                    slot.global = binding.actionID
                }
                newSpace[keyCode] = slot
                let action = binding.actionID.rawValue
                let combo = binding.rawCombo
                Log.keybindings.debug(
                    "  space key=\(keyCode, privacy: .public) → \(action, privacy: .public) (\(combo, privacy: .public))"
                )
            }
        }

        var newMouse: [MouseKey: BindingSlot] = [:]
        for binding in mouse {
            if case .mouseButton(let button, let modifiers) = binding.comboType {
                let key = MouseKey(button: button, modifiers: modifiers)
                var slot = newMouse[key] ?? BindingSlot()
                if let app = binding.app {
                    slot.appSpecific[app] = binding.actionID
                } else {
                    slot.global = binding.actionID
                }
                newMouse[key] = slot
                let action = binding.actionID.rawValue
                let combo = binding.rawCombo
                let fl = modifiers.rawValue
                Log.keybindings.debug(
                    "  mouse btn=\(button, privacy: .public) flags=\(fl, privacy: .public) → \(action, privacy: .public) (\(combo, privacy: .public))"
                )
            }
        }

        var newRemaps: [StandardKey: [String: RemapTarget]] = [:]
        for remap in remaps {
            if case .standard(let keyCode, let modifiers) = remap.fromType {
                let key = StandardKey(keyCode: keyCode, modifiers: modifiers)
                var appMap = newRemaps[key] ?? [:]
                appMap[remap.app] = RemapTarget(keyCode: remap.toKeyCode, modifiers: remap.toModifiers)
                newRemaps[key] = appMap
                Log.keybindings.debug(
                    "  remap \(remap.rawFrom, privacy: .public) → \(remap.rawTo, privacy: .public) [\(remap.app, privacy: .public)]"
                )
            }
        }

        var newMouseRemaps: [MouseKey: RemapTarget] = [:]
        for mr in mouseRemapList {
            let key = MouseKey(button: mr.button, modifiers: mr.modifiers)
            newMouseRemaps[key] = RemapTarget(keyCode: mr.toKeyCode, modifiers: mr.toModifiers)
            Log.keybindings.debug(
                "  mouseRemap \(mr.rawFrom, privacy: .public) → \(mr.rawTo, privacy: .public)"
            )
        }

        let std = newStandard.count
        let caps = newCapsLock.count
        let spc = newSpace.count
        let mse = newMouse.count
        let rmp = newRemaps.count
        let mrmp = newMouseRemaps.count
        let summary = "\(std)/\(caps)/\(spc)/\(mse)+\(rmp)rmp+\(mrmp)mrmp"
        Log.keybindings.debug("Bindings: \(summary, privacy: .public)")

        os_unfair_lock_lock(&lock)
        standardBindings = newStandard
        capsLockBindings = newCapsLock
        spaceBindings = newSpace
        mouseBindings = newMouse
        mouseRemaps = newMouseRemaps
        standardRemaps = newRemaps
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - Lookup Helpers (called from tap callback thread)

    private struct StandardKey: Hashable {
        let keyCode: UInt16
        let modifiers: CGEventFlags

        // Only compare the modifier bits we care about
        static func == (lhs: StandardKey, rhs: StandardKey) -> Bool {
            lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(keyCode)
            hasher.combine(modifiers.rawValue)
        }
    }

    private struct MouseKey: Hashable {
        let button: Int
        let modifiers: CGEventFlags

        static func == (lhs: MouseKey, rhs: MouseKey) -> Bool {
            lhs.button == rhs.button && lhs.modifiers == rhs.modifiers
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(button)
            hasher.combine(modifiers.rawValue)
        }
    }

    private static let relevantModifiers: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]

    private func maskedFlags(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(Self.relevantModifiers)
    }

    // MARK: - Event Handling

    fileprivate func handleEvent(
        proxy _: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port = tapPort {
                let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
                Log.keybindings.warning(
                    "Event tap disabled by \(reason, privacy: .public), re-enabling"
                )
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)

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
        os_unfair_lock_lock(&lock)
        let hasCapsBindings = !capsLockBindings.isEmpty
        os_unfair_lock_unlock(&lock)

        if hasCapsBindings {
            let keyCode = UInt16(
                event.getIntegerValueField(.keyboardEventKeycode)
            )
            if keyCode == UInt16(kVK_CapsLock) {
                return nil  // Suppress LED toggle
            }
            // Also strip alphaShift from other modifier events
            // so held capslock doesn't affect letter case.
            if event.flags.contains(.maskAlphaShift) {
                event.flags = event.flags.subtracting(.maskAlphaShift)
            }
        }

        return Unmanaged.passUnretained(event)
    }

    // swiftlint:disable:next function_body_length
    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Pass through events we injected ourselves (e.g. mouse remaps)
        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let spaceKeyCode = UInt16(kVK_Space)

        // Read focused app once for all lookups in this event
        let focusedApp = focusedAppTracker.focusedBundleID

        // Strip alphaShift so held capslock doesn't uppercase letters
        os_unfair_lock_lock(&lock)
        let stripCaps = !capsLockBindings.isEmpty
        os_unfair_lock_unlock(&lock)
        if stripCaps, event.flags.contains(.maskAlphaShift) {
            event.flags = event.flags.subtracting(.maskAlphaShift)
        }

        let flags = maskedFlags(event.flags)

        // Space-as-modifier: space key pressed
        if keyCode == spaceKeyCode, !spaceHeld {
            os_unfair_lock_lock(&lock)
            let hasSpaceBindings = !spaceBindings.isEmpty
            os_unfair_lock_unlock(&lock)

            if hasSpaceBindings {
                spaceHeld = true
                spaceUsedAsModifier = false
                return nil  // Suppress space character until we know if it's a modifier
            }
        }

        // Caps-lock modifier combos (state from IOKit HID)
        if CapsLockMonitor.shared.isPressed {
            os_unfair_lock_lock(&lock)
            let slot = capsLockBindings[keyCode]
            os_unfair_lock_unlock(&lock)

            if let actionID = slot?.resolve(focusedApp: focusedApp) {
                Log.keybindings.info(
                    "CapsLock+\(keyCode, privacy: .public) → \(actionID.rawValue, privacy: .public)"
                )
                executor(actionID)
                return nil
            }
        }

        // Space modifier combos
        if spaceHeld, keyCode != spaceKeyCode {
            os_unfair_lock_lock(&lock)
            let slot = spaceBindings[keyCode]
            os_unfair_lock_unlock(&lock)

            if let actionID = slot?.resolve(focusedApp: focusedApp) {
                spaceUsedAsModifier = true
                Log.keybindings.info(
                    "Space+\(keyCode, privacy: .public) → \(actionID.rawValue, privacy: .public)")
                executor(actionID)
                return nil
            }
        }

        // Standard modifier+key combos — check remaps first, then bindings
        let key = StandardKey(keyCode: keyCode, modifiers: flags)
        os_unfair_lock_lock(&lock)
        let remapTarget = standardRemaps[key]?[focusedApp]
        let bindingSlot = standardBindings[key]
        let bindingCount = standardBindings.count
        os_unfair_lock_unlock(&lock)

        // Remap: modify the event in-place and pass it through
        if let remap = remapTarget {
            Log.keybindings.info(
                "Remap key=\(keyCode, privacy: .public) → key=\(remap.keyCode, privacy: .public) [\(focusedApp, privacy: .public)]"
            )
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(remap.keyCode))
            // Set target modifiers, preserving non-relevant flags (e.g. alphaShift)
            let preserved = event.flags.subtracting(Self.relevantModifiers)
            event.flags = remap.modifiers.union(preserved)
            return Unmanaged.passUnretained(event)
        }

        // Action binding
        if let actionID = bindingSlot?.resolve(focusedApp: focusedApp) {
            let f = flags.rawValue
            Log.keybindings.info(
                "Key \(keyCode, privacy: .public) flags=\(f, privacy: .public) → \(actionID.rawValue, privacy: .public)"
            )
            executor(actionID)
            return nil
        }

        // Log unmatched events when modifiers are held (skip plain typing)
        if flags.rawValue != 0 {
            let f = flags.rawValue
            let cnt = bindingCount
            Log.keybindings.debug(
                "Unmatched keyDown: key=\(keyCode, privacy: .public) flags=\(f, privacy: .public) (\(cnt, privacy: .public) bindings)"
            )
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Pass through events we injected ourselves
        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedMarker {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let spaceKeyCode = UInt16(kVK_Space)

        // Strip alphaShift so held capslock doesn't uppercase letters
        os_unfair_lock_lock(&lock)
        let stripCaps = !capsLockBindings.isEmpty
        os_unfair_lock_unlock(&lock)
        if stripCaps, event.flags.contains(.maskAlphaShift) {
            event.flags = event.flags.subtracting(.maskAlphaShift)
        }

        if keyCode == spaceKeyCode, spaceHeld {
            spaceHeld = false
            if !spaceUsedAsModifier {
                // Space was tapped, not used as modifier — inject space keypress
                injectSpacePress()
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

        os_unfair_lock_lock(&lock)
        let remap = mouseRemaps[mouseKey]
        let slot = mouseBindings[mouseKey]
        os_unfair_lock_unlock(&lock)

        // Mouse remaps take priority — inject key event instead
        if let remap {
            Log.keybindings.info(
                "MouseRemap btn=\(button, privacy: .public) → key=\(remap.keyCode, privacy: .public)"
            )
            injectKeyPress(keyCode: remap.keyCode, modifiers: remap.modifiers)
            return nil
        }

        if let actionID = slot?.resolve(focusedApp: focusedApp) {
            let f = flags.rawValue
            Log.keybindings.info(
                "Mouse \(button, privacy: .public) flags=\(f, privacy: .public) → \(actionID.rawValue, privacy: .public)"
            )
            executor(actionID)
            return nil
        }

        let f = flags.rawValue
        Log.keybindings.debug(
            "Unmatched mouseDown: button=\(button, privacy: .public) flags=\(f, privacy: .public)"
        )

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Helpers

    /// Marker value set on `eventSourceUserData` so the tap recognises
    /// injected events and passes them through untouched.
    private static let injectedMarker: Int64 = 0x5649_4245  // "VIBE"

    private func injectKeyPress(keyCode: UInt16, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            down.flags = modifiers
            up.flags = modifiers
            down.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
            up.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }

    private func injectSpacePress() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let spaceCode = UInt16(kVK_Space)

        if let down = CGEvent(keyboardEventSource: source, virtualKey: spaceCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: spaceCode, keyDown: false) {
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
