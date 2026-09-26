import ApplicationServices
import CoreGraphics
import Foundation

/// Formats a menu item's keyboard shortcut from its accessibility attributes the
/// way the menu draws it: "⇧⌘T", "⌃⌥←", "fn⌃F".
enum MenuShortcut {
    /// Not in AXAttributeConstants.h, but apps report it for fn/🌐 shortcuts
    /// (Window › Fill is fn⌃F).
    private static let function = AXMenuItemModifiers(rawValue: 1 << 4)

    /// `modifiers` is the raw AXMenuItemCmdModifiers value: ⌘ is implied unless
    /// `.noCommand` is set.
    static func format(character: String?, virtualKey: Int?, modifiers: Int) -> String? {
        guard let key = keyLabel(character: character, virtualKey: virtualKey) else { return nil }
        let mask = AXMenuItemModifiers(rawValue: UInt32(truncatingIfNeeded: modifiers))
        var flags: CGEventFlags = []
        if mask.contains(.control) { flags.insert(.maskControl) }
        if mask.contains(.option) { flags.insert(.maskAlternate) }
        if mask.contains(.shift) { flags.insert(.maskShift) }
        if !mask.contains(.noCommand) { flags.insert(.maskCommand) }
        let fn = mask.contains(function) ? "fn" : ""
        return fn + KeystrokeFormatter.modifierSymbols(flags) + key
    }

    private static func keyLabel(character: String?, virtualKey: Int?) -> String? {
        // Special keys (arrows, F-keys, ⎋, ⌫) come with a virtual key code; letter
        // and punctuation shortcuts only carry the character.
        if let virtualKey, let keyCode = UInt16(exactly: virtualKey) {
            return KeystrokeFormatter.keyLabel(for: keyCode, characters: character ?? "")
        }
        guard let character, !character.isEmpty,
              !character.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return nil
        }
        return character.uppercased()
    }
}
