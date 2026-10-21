import Carbon.HIToolbox
import CoreGraphics
import Foundation
import ShowreelCore

/// Synthesizes keystrokes at the HID level, ahead of every event tap, so
/// Vibeshed's keybindings and keystroke visualizer see them like real ones.
@MainActor
enum Keyboard {
    private static let source = CGEventSource(stateID: .hidSystemState)

    /// Flags a real left-hand modifier sets, device bits included: some
    /// consumers ignore modifiers without them.
    private static func flags(for modifier: KeyChord.Modifier) -> UInt64 {
        switch modifier {
        case .capsLock: 0
        case .control: 0x40001
        case .option: 0x80020
        case .shift: 0x20002
        case .command: 0x100008
        case .function: 0x800000
        }
    }

    static func press(_ press: KeyPress) async throws {
        for index in 0 ..< max(1, press.times) {
            if index > 0 { try await Task.sleep(for: .seconds(press.interval)) }
            try await tap(press.chord)
        }
    }

    static func tap(_ chord: KeyChord) async throws {
        try SystemDialogs.ensureNone()
        var held: UInt64 = 0
        for modifier in chord.modifiers {
            held |= flags(for: modifier)
            post(modifier.keyCode, down: true, flags: held, isModifier: modifier != .capsLock)
            try await Task.sleep(for: .milliseconds(35))
        }
        post(chord.keyCode, down: true, flags: held)
        try await Task.sleep(for: .milliseconds(45))
        post(chord.keyCode, down: false, flags: held)
        for modifier in chord.modifiers.reversed() {
            try await Task.sleep(for: .milliseconds(25))
            held &= ~flags(for: modifier)
            post(modifier.keyCode, down: false, flags: held, isModifier: modifier != .capsLock)
        }
    }

    static func type(_ typing: TypeText) async throws {
        let layout = KeyboardLayout.current()
        var random = SeededRandom(seed: UInt64(truncatingIfNeeded: typing.text.hashValueStable))
        let average = 1 / max(typing.cps, 1)
        for character in typing.text {
            if let key = layout[String(character)] ?? KeyCodes.ansiCharacters[String(character)] {
                let shift = KeyChord.Modifier.shift
                let chord = KeyChord(modifiers: key.shift ? [shift] : [], keyCode: key.keyCode, keyName: "")
                try await tap(chord)
            } else {
                try SystemDialogs.ensureNone()
                postUnicode(String(character))
            }
            let jitter = (random.nextUnit() * 2 - 1) * typing.jitter
            try await Task.sleep(for: .seconds(max(0.015, average * (1 + jitter))))
        }
    }

    private static func post(_ keyCode: UInt16, down: Bool, flags: UInt64, isModifier: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        if isModifier {
            event.type = .flagsChanged
            // A real modifier event also carries the non-coalesced bit.
            event.flags = CGEventFlags(rawValue: flags | 0x100)
        } else {
            event.flags = CGEventFlags(rawValue: flags)
        }
        event.post(tap: .cghidEventTap)
    }

    /// For characters no key on the current layout types (emoji, accents).
    private static func postUnicode(_ text: String) {
        let units = Array(text.utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            event.post(tap: .cghidEventTap)
        }
    }
}

/// The current input source's characters, mapped back to the keys that type them.
enum KeyboardLayout {
    static func current() -> [String: (keyCode: UInt16, shift: Bool)] {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var map: [String: (keyCode: UInt16, shift: Bool)] = [:]
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for shift in [false, true] {
                for keyCode in UInt16(0) ..< 128 {
                    guard let text = translate(keyCode, shift: shift, layout: layout), map[text] == nil else {
                        continue
                    }
                    map[text] = (keyCode, shift)
                }
            }
        }
        return map
    }

    private static func translate(_ keyCode: UInt16, shift: Bool, layout: UnsafePointer<UCKeyboardLayout>) -> String? {
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let modifiers: UInt32 = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
        let status = UCKeyTranslate(
            layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
        )
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: chars, count: length)
        // Skip control characters (return, tab, arrows…): `press` handles those keys.
        return text.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) ? text : nil
    }
}

/// splitmix64: a tiny deterministic generator, so a scene types with the same
/// rhythm on every take.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func nextUnit() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }
}

extension String {
    /// FNV-1a: unlike `hashValue`, the same in every process.
    var hashValueStable: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return hash
    }
}
