import CoreGraphics

// MARK: - CapsLock Combos (tap callback thread)

extension EventTapHandler {
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
