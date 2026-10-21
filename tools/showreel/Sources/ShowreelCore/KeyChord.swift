import Foundation

/// A key with the modifiers held while it is pressed, parsed from scene text
/// like `cmd+shift+4`, `capslock+space` or `down`.
public struct KeyChord: Equatable, Sendable, CustomStringConvertible {
    public enum Modifier: String, CaseIterable, Sendable {
        /// Held as F18, the way a host Vibeshed forwards CapsLock into a VM:
        /// a synthesized CapsLock never reaches Vibeshed's IOKit HID monitor,
        /// while F18 goes through its event tap.
        case capsLock
        case control
        case option
        case shift
        case command
        case function

        public var keyCode: UInt16 {
            switch self {
            case .capsLock: KeyCodes.f18
            case .control: 59
            case .option: 58
            case .shift: 56
            case .command: 55
            case .function: 63
            }
        }
    }

    /// Modifiers in press order: CapsLock first, like a held layer key.
    public var modifiers: [Modifier]
    public var keyCode: UInt16
    public var keyName: String

    public init(modifiers: [Modifier], keyCode: UInt16, keyName: String) {
        self.modifiers = modifiers
        self.keyCode = keyCode
        self.keyName = keyName
    }

    public var description: String {
        (modifiers.map(\.rawValue) + [keyName]).joined(separator: "+")
    }

    public static func parse(_ text: String) throws -> KeyChord {
        let tokens = text.split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let keyToken = tokens.last, !keyToken.isEmpty, !tokens.contains("") else {
            throw SceneError.invalid("key chord '\(text)' has an empty part")
        }
        var modifiers: [Modifier] = []
        for token in tokens.dropLast() {
            guard let modifier = modifierNames[token] else {
                throw SceneError.invalid("unknown modifier '\(token)' in '\(text)'")
            }
            if !modifiers.contains(modifier) {
                modifiers.append(modifier)
            }
        }
        modifiers.sort { Modifier.allCases.firstIndex(of: $0)! < Modifier.allCases.firstIndex(of: $1)! }
        guard let keyCode = KeyCodes.named[keyToken] ?? KeyCodes.ansiCharacters[keyToken].map(\.keyCode) else {
            throw SceneError.invalid("unknown key '\(keyToken)' in '\(text)'")
        }
        return KeyChord(modifiers: modifiers, keyCode: keyCode, keyName: keyToken)
    }

    private static let modifierNames: [String: Modifier] = [
        "capslock": .capsLock, "caps": .capsLock, "⇪": .capsLock,
        "ctrl": .control, "control": .control, "⌃": .control,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
        "cmd": .command, "command": .command, "⌘": .command,
        "fn": .function,
    ]
}

/// macOS virtual key codes (ANSI layout), as in Carbon's `kVK_*` constants.
public enum KeyCodes {
    public static let f18: UInt16 = 79

    public static let named: [String: UInt16] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "forwarddelete": 117, "home": 115, "end": 119,
        "pageup": 116, "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "f13": 105, "f14": 107, "f15": 113,
        "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "minus": 27, "equal": 24, "plus": 24, "comma": 43, "period": 47, "slash": 44,
        "backslash": 42, "semicolon": 41, "quote": 39, "grave": 50,
        "leftbracket": 33, "rightbracket": 30,
    ]

    /// Characters an ANSI US keyboard types, with whether Shift is needed.
    public static let ansiCharacters: [String: (keyCode: UInt16, shift: Bool)] = {
        var map: [String: (keyCode: UInt16, shift: Bool)] = [:]
        let plain: [(String, UInt16)] = [
            ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8),
            ("v", 9), ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17),
            ("1", 18), ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24), ("9", 25),
            ("7", 26), ("-", 27), ("8", 28), ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33),
            ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("'", 39), ("k", 40), (";", 41), ("\\", 42),
            (",", 43), ("/", 44), ("n", 45), ("m", 46), (".", 47), ("`", 50), (" ", 49),
        ]
        let shifted: [(String, String)] = [
            ("!", "1"), ("@", "2"), ("#", "3"), ("$", "4"), ("%", "5"), ("^", "6"), ("&", "7"),
            ("*", "8"), ("(", "9"), (")", "0"), ("_", "-"), ("+", "="), ("{", "["), ("}", "]"),
            ("|", "\\"), (":", ";"), ("\"", "'"), ("<", ","), (">", "."), ("?", "/"), ("~", "`"),
        ]
        for (char, code) in plain {
            map[char] = (code, false)
            if char.count == 1, char.first!.isLetter {
                map[char.uppercased()] = (code, true)
            }
        }
        for (char, base) in shifted {
            map[char] = (map[base]!.keyCode, true)
        }
        return map
    }()
}
