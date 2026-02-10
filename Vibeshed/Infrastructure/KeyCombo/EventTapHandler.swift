import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

final class EventTapHandler: @unchecked Sendable {
    private let executor: @Sendable (ActionID) -> Void

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var thread: Thread?

    // Binding tables — guarded by lock
    private var lock = os_unfair_lock()
    private var standardBindings: [StandardKey: ActionID] = [:]
    private var capsLockBindings: [UInt16: ActionID] = [:]
    private var spaceBindings: [UInt16: ActionID] = [:]
    private var mouseBindings: [MouseKey: ActionID] = [:]

    // Modifier hold state — only accessed from tap callback thread
    private var capsLockHeld = false
    private var capsLockUsedAsModifier = false
    private var spaceHeld = false
    private var spaceUsedAsModifier = false

    init(executor: @escaping @Sendable (ActionID) -> Void) {
        self.executor = executor
    }

    deinit {
        stop()
    }

    // MARK: - Public

    func start() {
        guard tapPort == nil else { return }

        let eventMask: CGEventMask = (
            (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.otherMouseDown.rawValue)
                | (1 << CGEventType.otherMouseUp.rawValue)
        )

        // `self` is passed as userInfo to the C callback
        let unmanaged = Unmanaged.passRetained(self)

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: unmanaged.toOpaque()
        ) else {
            unmanaged.release()
            Log.keybindings.error("Failed to create CGEventTap — accessibility permission likely missing")
            return
        }

        tapPort = port

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source

        let tapThread = Thread { [weak self] in
            guard let self, let source else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        tapThread.name = "com.vibeshed.eventtap"
        tapThread.qualityOfService = .userInteractive
        tapThread.start()
        thread = tapThread

        Log.keybindings.info("Event tap started")
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
        if tapPort != nil {
            Unmanaged<EventTapHandler>.passUnretained(self).release()
        }
        tapPort = nil
        runLoopSource = nil
        tapRunLoop = nil
        thread = nil

        Log.keybindings.info("Event tap stopped")
    }

    func updateBindings(
        standard: [ResolvedBinding],
        capsLock: [ResolvedBinding],
        space: [ResolvedBinding],
        mouse: [ResolvedBinding]
    ) {
        var newStandard: [StandardKey: ActionID] = [:]
        for binding in standard {
            if case let .standard(keyCode, modifiers) = binding.comboType {
                newStandard[StandardKey(keyCode: keyCode, modifiers: modifiers)] = binding.actionID
            }
        }

        var newCapsLock: [UInt16: ActionID] = [:]
        for binding in capsLock {
            if case let .capsLockModifier(keyCode) = binding.comboType {
                newCapsLock[keyCode] = binding.actionID
            }
        }

        var newSpace: [UInt16: ActionID] = [:]
        for binding in space {
            if case let .spaceModifier(keyCode) = binding.comboType {
                newSpace[keyCode] = binding.actionID
            }
        }

        var newMouse: [MouseKey: ActionID] = [:]
        for binding in mouse {
            if case let .mouseButton(button, modifiers) = binding.comboType {
                newMouse[MouseKey(button: button, modifiers: modifiers)] = binding.actionID
            }
        }

        os_unfair_lock_lock(&lock)
        standardBindings = newStandard
        capsLockBindings = newCapsLock
        spaceBindings = newSpace
        mouseBindings = newMouse
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
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let capsLockKeyCode: UInt16 = UInt16(kVK_CapsLock)

        guard keyCode == capsLockKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        os_unfair_lock_lock(&lock)
        let hasCapsBindings = !capsLockBindings.isEmpty
        os_unfair_lock_unlock(&lock)

        guard hasCapsBindings else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let capsLockOn = flags.contains(.maskAlphaShift)

        if capsLockOn, !capsLockHeld {
            // Caps lock just pressed
            capsLockHeld = true
            capsLockUsedAsModifier = false
            return nil // Suppress to prevent LED toggle
        } else if !capsLockOn, capsLockHeld {
            // Caps lock released
            capsLockHeld = false
            if !capsLockUsedAsModifier {
                // Was tapped without combo — pass through original toggle
                return Unmanaged.passUnretained(event)
            }
            return nil // Suppress if used as modifier
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let spaceKeyCode = UInt16(kVK_Space)
        let flags = maskedFlags(event.flags)

        // Space-as-modifier: space key pressed
        if keyCode == spaceKeyCode, !spaceHeld {
            os_unfair_lock_lock(&lock)
            let hasSpaceBindings = !spaceBindings.isEmpty
            os_unfair_lock_unlock(&lock)

            if hasSpaceBindings {
                spaceHeld = true
                spaceUsedAsModifier = false
                return nil // Suppress space character until we know if it's a modifier
            }
        }

        // Caps-lock modifier combos
        if capsLockHeld {
            os_unfair_lock_lock(&lock)
            let actionID = capsLockBindings[keyCode]
            os_unfair_lock_unlock(&lock)

            if let actionID {
                capsLockUsedAsModifier = true
                executor(actionID)
                return nil
            }
        }

        // Space modifier combos
        if spaceHeld, keyCode != spaceKeyCode {
            os_unfair_lock_lock(&lock)
            let actionID = spaceBindings[keyCode]
            os_unfair_lock_unlock(&lock)

            if let actionID {
                spaceUsedAsModifier = true
                executor(actionID)
                return nil
            }
        }

        // Standard modifier+key combos
        os_unfair_lock_lock(&lock)
        let actionID = standardBindings[StandardKey(keyCode: keyCode, modifiers: flags)]
        os_unfair_lock_unlock(&lock)

        if let actionID {
            executor(actionID)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyUp(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let spaceKeyCode = UInt16(kVK_Space)

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

        os_unfair_lock_lock(&lock)
        let actionID = mouseBindings[MouseKey(button: button, modifiers: flags)]
        os_unfair_lock_unlock(&lock)

        if let actionID {
            executor(actionID)
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - Helpers

    private func injectSpacePress() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let spaceCode = UInt16(kVK_Space)

        if let down = CGEvent(keyboardEventSource: source, virtualKey: spaceCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: spaceCode, keyDown: false)
        {
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
