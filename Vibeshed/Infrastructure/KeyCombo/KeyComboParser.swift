import Carbon.HIToolbox
import CoreGraphics

enum KeyComboParser {
    static func parse(_ combo: String) throws -> KeyComboType {
        let components = combo.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        guard !components.isEmpty else {
            throw KeyComboError.invalidCombo(combo, reason: "empty combo string")
        }

        // Mouse button binding: any component starting with "mouse"
        if let mouseIndex = components.firstIndex(where: { $0.hasPrefix("mouse") }) {
            let mouseStr = components[mouseIndex]
            guard let buttonNum = Int(mouseStr.dropFirst(5)), buttonNum >= 1 else {
                throw KeyComboError.invalidCombo(combo, reason: "invalid mouse button '\(mouseStr)'")
            }
            // mouse1=0(left), mouse2=1(right), mouse3=2(middle), mouse4=3(back), mouse5=4(forward)
            let cgButton = buttonNum - 1
            var modifiers = CGEventFlags()
            for (i, comp) in components.enumerated() where i != mouseIndex {
                modifiers.insert(try modifierFlag(for: comp))
            }
            return .mouseButton(button: cgButton, modifiers: modifiers)
        }

        // Caps-lock as modifier
        if let capsIndex = components.firstIndex(of: "capslock") {
            let otherComponents = components.enumerated()
                .filter { $0.offset != capsIndex }
                .map(\.element)
            guard otherComponents.count == 1 else {
                throw KeyComboError.invalidCombo(
                    combo,
                    reason: "capslock modifier requires exactly one key"
                )
            }
            let keyCode = try carbonKeyCode(for: otherComponents[0])
            return .capsLockModifier(carbonKeyCode: keyCode)
        }

        // Space as modifier: "space" + another key
        if components.contains("space"), components.count == 2,
           let otherKey = components.first(where: { $0 != "space" }) {
            // Check if the other component is a regular key (not a modifier name)
            if modifierNames[otherKey] == nil {
                let keyCode = try carbonKeyCode(for: otherKey)
                return .spaceModifier(carbonKeyCode: keyCode)
            }
        }

        // Tab as modifier: "tab" + another key
        if components.contains("tab"), components.count == 2,
           let otherKey = components.first(where: { $0 != "tab" }) {
            if modifierNames[otherKey] == nil {
                let keyCode = try carbonKeyCode(for: otherKey)
                return .tabModifier(carbonKeyCode: keyCode)
            }
        }

        // Standard combo: modifiers + key (last component is the key)
        guard let keyName = components.last else {
            throw KeyComboError.invalidCombo(combo, reason: "no key specified")
        }
        let keyCode = try carbonKeyCode(for: keyName)
        var modifiers = CGEventFlags()
        for comp in components.dropLast() {
            modifiers.insert(try modifierFlag(for: comp))
        }
        return .standard(carbonKeyCode: keyCode, modifiers: modifiers)
    }

    /// Parse a combo string and extract keyCode + modifiers for standard combos only.
    /// Used for remap targets where we need the raw key data.
    static func parseStandard(_ combo: String) throws -> (keyCode: UInt16, modifiers: CGEventFlags) {
        let comboType = try parse(combo)
        guard case .standard(let keyCode, let modifiers) = comboType else {
            throw KeyComboError.invalidCombo(
                combo,
                reason: "remap target must be a standard key combo (not capslock/space/mouse)"
            )
        }
        return (keyCode, modifiers)
    }

    static func carbonKeyCode(for name: String) throws -> UInt16 {
        guard let code = keyCodes[name.lowercased()] else {
            throw KeyComboError.unknownKey(name)
        }
        return code
    }

    static func modifierFlag(for name: String) throws -> CGEventFlags {
        guard let flag = modifierNames[name.lowercased()] else {
            throw KeyComboError.unknownModifier(name)
        }
        return flag
    }

    // MARK: - Key Code Dictionary

    private static let keyCodes: [String: UInt16] = {
        var map: [String: UInt16] = [:]

        // Letters
        map["a"] = UInt16(kVK_ANSI_A)
        map["b"] = UInt16(kVK_ANSI_B)
        map["c"] = UInt16(kVK_ANSI_C)
        map["d"] = UInt16(kVK_ANSI_D)
        map["e"] = UInt16(kVK_ANSI_E)
        map["f"] = UInt16(kVK_ANSI_F)
        map["g"] = UInt16(kVK_ANSI_G)
        map["h"] = UInt16(kVK_ANSI_H)
        map["i"] = UInt16(kVK_ANSI_I)
        map["j"] = UInt16(kVK_ANSI_J)
        map["k"] = UInt16(kVK_ANSI_K)
        map["l"] = UInt16(kVK_ANSI_L)
        map["m"] = UInt16(kVK_ANSI_M)
        map["n"] = UInt16(kVK_ANSI_N)
        map["o"] = UInt16(kVK_ANSI_O)
        map["p"] = UInt16(kVK_ANSI_P)
        map["q"] = UInt16(kVK_ANSI_Q)
        map["r"] = UInt16(kVK_ANSI_R)
        map["s"] = UInt16(kVK_ANSI_S)
        map["t"] = UInt16(kVK_ANSI_T)
        map["u"] = UInt16(kVK_ANSI_U)
        map["v"] = UInt16(kVK_ANSI_V)
        map["w"] = UInt16(kVK_ANSI_W)
        map["x"] = UInt16(kVK_ANSI_X)
        map["y"] = UInt16(kVK_ANSI_Y)
        map["z"] = UInt16(kVK_ANSI_Z)

        // Digits
        map["0"] = UInt16(kVK_ANSI_0)
        map["1"] = UInt16(kVK_ANSI_1)
        map["2"] = UInt16(kVK_ANSI_2)
        map["3"] = UInt16(kVK_ANSI_3)
        map["4"] = UInt16(kVK_ANSI_4)
        map["5"] = UInt16(kVK_ANSI_5)
        map["6"] = UInt16(kVK_ANSI_6)
        map["7"] = UInt16(kVK_ANSI_7)
        map["8"] = UInt16(kVK_ANSI_8)
        map["9"] = UInt16(kVK_ANSI_9)

        // Function keys
        map["f1"] = UInt16(kVK_F1)
        map["f2"] = UInt16(kVK_F2)
        map["f3"] = UInt16(kVK_F3)
        map["f4"] = UInt16(kVK_F4)
        map["f5"] = UInt16(kVK_F5)
        map["f6"] = UInt16(kVK_F6)
        map["f7"] = UInt16(kVK_F7)
        map["f8"] = UInt16(kVK_F8)
        map["f9"] = UInt16(kVK_F9)
        map["f10"] = UInt16(kVK_F10)
        map["f11"] = UInt16(kVK_F11)
        map["f12"] = UInt16(kVK_F12)
        map["f13"] = UInt16(kVK_F13)
        map["f14"] = UInt16(kVK_F14)
        map["f15"] = UInt16(kVK_F15)
        map["f16"] = UInt16(kVK_F16)
        map["f17"] = UInt16(kVK_F17)
        map["f18"] = UInt16(kVK_F18)
        map["f19"] = UInt16(kVK_F19)
        map["f20"] = UInt16(kVK_F20)

        // Arrows
        map["left"] = UInt16(kVK_LeftArrow)
        map["right"] = UInt16(kVK_RightArrow)
        map["up"] = UInt16(kVK_UpArrow)
        map["down"] = UInt16(kVK_DownArrow)

        // Special keys
        map["return"] = UInt16(kVK_Return)
        map["enter"] = UInt16(kVK_Return)
        map["tab"] = UInt16(kVK_Tab)
        map["space"] = UInt16(kVK_Space)
        map["delete"] = UInt16(kVK_Delete)
        map["backspace"] = UInt16(kVK_Delete)
        map["forwarddelete"] = UInt16(kVK_ForwardDelete)
        map["escape"] = UInt16(kVK_Escape)
        map["esc"] = UInt16(kVK_Escape)
        map["home"] = UInt16(kVK_Home)
        map["end"] = UInt16(kVK_End)
        map["pageup"] = UInt16(kVK_PageUp)
        map["pagedown"] = UInt16(kVK_PageDown)

        // Punctuation
        map["minus"] = UInt16(kVK_ANSI_Minus)
        map["-"] = UInt16(kVK_ANSI_Minus)
        map["equal"] = UInt16(kVK_ANSI_Equal)
        map["="] = UInt16(kVK_ANSI_Equal)
        map["leftbracket"] = UInt16(kVK_ANSI_LeftBracket)
        map["["] = UInt16(kVK_ANSI_LeftBracket)
        map["rightbracket"] = UInt16(kVK_ANSI_RightBracket)
        map["]"] = UInt16(kVK_ANSI_RightBracket)
        map["semicolon"] = UInt16(kVK_ANSI_Semicolon)
        map[";"] = UInt16(kVK_ANSI_Semicolon)
        map["quote"] = UInt16(kVK_ANSI_Quote)
        map["'"] = UInt16(kVK_ANSI_Quote)
        map["comma"] = UInt16(kVK_ANSI_Comma)
        map[","] = UInt16(kVK_ANSI_Comma)
        map["period"] = UInt16(kVK_ANSI_Period)
        map["."] = UInt16(kVK_ANSI_Period)
        map["slash"] = UInt16(kVK_ANSI_Slash)
        map["/"] = UInt16(kVK_ANSI_Slash)
        map["backslash"] = UInt16(kVK_ANSI_Backslash)
        map["\\"] = UInt16(kVK_ANSI_Backslash)
        map["backtick"] = UInt16(kVK_ANSI_Grave)
        map["`"] = UInt16(kVK_ANSI_Grave)

        return map
    }()

    private static let modifierNames: [String: CGEventFlags] = [
        "cmd": .maskCommand,
        "command": .maskCommand,
        "ctrl": .maskControl,
        "control": .maskControl,
        "option": .maskAlternate,
        "alt": .maskAlternate,
        "shift": .maskShift,
    ]
}
