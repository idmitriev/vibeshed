import Carbon.HIToolbox
import CoreGraphics

// MARK: - CapsLock Combos (tap callback thread)

extension EventTapHandler {
    func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !currentTables().capsLock.isEmpty else { return Unmanaged.passUnretained(event) }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // CapsLock state is tracked via IOKit HID (CapsLockMonitor). Suppress
        // the capslock flagsChanged event to prevent the LED toggle, and keep
        // the system toggle off so excluded apps (e.g. UTM, which syncs its
        // guest to it) start from a known state.
        if keyCode == UInt16(kVK_CapsLock) {
            SystemCapsLock.turnOff()
            return nil
        }

        // Around that toggle the system also sends flagsChanged events with a
        // non-modifier key code: 255 right after it, and the next key's own
        // code (49 for capslock+space) just before that key's keyDown. WebKit
        // turns each into a DOM keydown that never gets a keyup. Whenever one
        // beat the picker to the focus, YouTube took Space as held and played at 2x.
        guard Self.modifierKeyCodes.contains(keyCode) else { return nil }

        // Also strip alphaShift from other modifier events
        // so held capslock doesn't affect letter case.
        if event.flags.contains(.maskAlphaShift) {
            event.flags = event.flags.subtracting(.maskAlphaShift)
        }
        return Unmanaged.passUnretained(event)
    }

    /// kVK_RightCommand (0x36) through kVK_Function (0x3F): the keys a real
    /// flagsChanged event comes from.
    private static let modifierKeyCodes = UInt16(kVK_RightCommand)...UInt16(kVK_Function)

    /// CapsLock + key combos, with capslock's state from IOKit HID. True when
    /// the key press was consumed.
    func handleCapsLockCombo(
        event: CGEvent,
        keyCode: UInt16,
        focusedApp: String,
        tables: BindingTables
    ) -> Bool {
        let actionID = CapsLockMonitor.shared.isPressed
            ? tables.capsLock[keyCode]?.resolve(focusedApp: focusedApp)
            : nil
        let outcome = capsLockPresses.keyDown(keyCode, isRepeat: Self.isAutorepeat(event), comboIsHeld: actionID != nil)
        if outcome == .fire, let actionID {
            Log.keybindings.info(
                "CapsLock+\(keyCode, privacy: .public) → \(actionID.rawValue, privacy: .public)"
            )
            keystrokes.reportKeyDown(event, keyCode: keyCode, heldKey: .capsLock, outcome: .binding(actionID))
            executor(actionID)
        }
        return outcome != .pass
    }

    /// In an excluded app: true for the repeats and keyUp of a combo pressed
    /// before the app took focus (say capslock+1 bringing UTM forward), which
    /// stay out of it like the keyDown did.
    func endsCapsLockComboInExcludedApp(event: CGEvent, type: CGEventType) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        switch type {
        case .keyDown:
            return capsLockPresses.keyDown(keyCode, isRepeat: Self.isAutorepeat(event), comboIsHeld: false) == .swallow
        case .keyUp:
            return capsLockPresses.keyUp(keyCode)
        default:
            return false
        }
    }

    private static func isAutorepeat(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    }
}
