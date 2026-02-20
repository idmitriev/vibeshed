import CoreGraphics
import Foundation

struct KeyBindingEntry: Codable, Sendable, Equatable {
    let combo: String
    let action: String
    let app: String?

    init(combo: String, action: String, app: String? = nil) {
        self.combo = combo
        self.action = action
        self.app = app
    }
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
    let app: String?
}

// MARK: - App Remaps

struct AppRemapGroup: Codable, Sendable, Equatable {
    let app: String
    let remaps: [RemapEntry]
}

struct RemapEntry: Codable, Sendable, Equatable {
    let from: String
    let to: String
}

struct ResolvedRemap: Sendable, Equatable {
    let fromType: KeyComboType
    let toKeyCode: UInt16
    let toModifiers: CGEventFlags
    let app: String
    let rawFrom: String
    let rawTo: String
}
