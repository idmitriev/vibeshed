import CoreGraphics
import Foundation

struct KeyBindingEntry: Codable, Sendable, Equatable {
    let combo: String
    let action: String
}

enum KeyComboType: Sendable, Equatable {
    case standard(carbonKeyCode: UInt16, modifiers: CGEventFlags)
    case capsLockModifier(carbonKeyCode: UInt16)
    case spaceModifier(carbonKeyCode: UInt16)
    case mouseButton(button: Int, modifiers: CGEventFlags)
}

struct ResolvedBinding: Sendable, Equatable {
    let comboType: KeyComboType
    let actionID: ActionID
    let rawCombo: String
}
