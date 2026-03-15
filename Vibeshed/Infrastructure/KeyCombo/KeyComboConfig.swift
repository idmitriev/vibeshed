import CoreGraphics
import Foundation

struct KeyBindingEntry: Codable, Sendable, Equatable {
    let combo: String
    let action: String?
    let remap: String?
    let app: String?

    init(combo: String, action: String? = nil, remap: String? = nil, app: String? = nil) {
        self.combo = combo
        self.action = action
        self.remap = remap
        self.app = app
    }
}

enum KeyComboType: Sendable, Equatable {
    case standard(carbonKeyCode: UInt16, modifiers: CGEventFlags)
    case capsLockModifier(carbonKeyCode: UInt16)
    case spaceModifier(carbonKeyCode: UInt16)
    case tabModifier(carbonKeyCode: UInt16)
    case mouseButton(button: Int, modifiers: CGEventFlags)
}

struct ResolvedBinding: Sendable, Equatable {
    let comboType: KeyComboType
    let actionID: ActionID
    let rawCombo: String
    let app: String?
}

// MARK: - Resolved Remaps

struct ResolvedMouseRemap: Sendable, Equatable {
    let button: Int
    let modifiers: CGEventFlags
    let toKeyCode: UInt16
    let toModifiers: CGEventFlags
    let rawFrom: String
    let rawTo: String
}

struct ResolvedRemap: Sendable, Equatable {
    let fromType: KeyComboType
    let toKeyCode: UInt16
    let toModifiers: CGEventFlags
    let app: String?
    let rawFrom: String
    let rawTo: String
}
