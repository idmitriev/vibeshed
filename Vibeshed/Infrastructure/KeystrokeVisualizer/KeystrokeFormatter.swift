import Carbon.HIToolbox
import CoreGraphics

/// Turns keystrokes into the labels the visualizer shows: "⌃⌥H", "⇪J", "Mouse 4".
enum KeystrokeFormatter {
    /// The text a keystroke adds to a run of plain typing, or nil when it
    /// should stand alone as a combo (a ⌘/⌃ chord, Return, an arrow, …).
    static func typedText(for keystroke: KeystrokeEvent) -> String? {
        guard keystroke.outcome == .passedThrough, keystroke.heldKey == nil,
              keystroke.modifiers.isDisjoint(with: [.maskCommand, .maskControl]),
              case let .key(keyCode, characters) = keystroke.input
        else {
            return nil
        }
        switch Int(keyCode) {
        case kVK_Space: return "␣"
        case kVK_Delete: return "⌫"
        default: break
        }
        // Function and navigation keys type private-use characters (U+F700…).
        let unprintable: Set<Unicode.GeneralCategory> = [.control, .privateUse]
        guard symbols[keyCode] == nil, !characters.isEmpty,
              !characters.unicodeScalars.contains(where: { unprintable.contains($0.properties.generalCategory) })
        else {
            return nil
        }
        return characters
    }

    /// The pressed chord, held layer key first: "⇪H", "⌃⌥⌘←", "⇧Mouse 4".
    static func comboLabel(for keystroke: KeystrokeEvent) -> String {
        let trigger = switch keystroke.input {
        case let .key(keyCode, characters): keyLabel(for: keyCode, characters: characters)
        case let .mouse(button): "Mouse \(button + 1)"
        }
        return heldKeySymbol(keystroke.heldKey) + modifierSymbols(keystroke.modifiers) + trigger
    }

    static func comboLabel(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        modifierSymbols(modifiers) + keyLabel(for: keyCode, characters: "")
    }

    /// Modifiers in Apple's menu order.
    static func modifierSymbols(_ flags: CGEventFlags) -> String {
        var result = ""
        if flags.contains(.maskControl) { result += "⌃" }
        if flags.contains(.maskAlternate) { result += "⌥" }
        if flags.contains(.maskShift) { result += "⇧" }
        if flags.contains(.maskCommand) { result += "⌘" }
        return result
    }

    /// Chords are labelled by the physical (ANSI) key, like menu shortcuts, so
    /// ⌘C reads the same under any layout; unknown keys fall back to what they type.
    static func keyLabel(for keyCode: UInt16, characters: String) -> String {
        if let symbol = symbols[keyCode] {
            return symbol
        }
        if let name = KeyComboParser.keyName(for: keyCode) {
            return name.uppercased()
        }
        let typed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? "key \(keyCode)" : typed.uppercased()
    }

    private static func heldKeySymbol(_ heldKey: KeystrokeEvent.HeldKey?) -> String {
        switch heldKey {
        case .capsLock: "⇪"
        case .space: "␣"
        case .tab: "⇥"
        case nil: ""
        }
    }

    private static let symbols: [UInt16: String] = [
        UInt16(kVK_Return): "↩",
        UInt16(kVK_ANSI_KeypadEnter): "⌤",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Space): "␣",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]
}
