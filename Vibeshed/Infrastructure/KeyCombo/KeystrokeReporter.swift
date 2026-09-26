import CoreGraphics
import os

/// Hands the event tap's keystrokes to the keystroke visualizer. The sink is
/// set from the main actor and called on the tap callback thread; with no sink
/// set, a report costs one lock round-trip.
final class KeystrokeReporter: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var sink: (@Sendable (KeystrokeEvent) -> Void)?

    func setSink(_ newValue: (@Sendable (KeystrokeEvent) -> Void)?) {
        os_unfair_lock_lock(&lock)
        sink = newValue
        os_unfair_lock_unlock(&lock)
    }

    /// Call before a remap rewrites `event`, so the key is reported as pressed.
    func reportKeyDown(
        _ event: CGEvent,
        keyCode: UInt16,
        heldKey: KeystrokeEvent.HeldKey? = nil,
        outcome: KeystrokeEvent.Outcome
    ) {
        guard let sink = currentSink() else { return }
        sink(KeystrokeEvent(
            input: .key(keyCode: keyCode, characters: Self.characters(of: event)),
            modifiers: event.flags.intersection(KeystrokeEvent.chordModifiers),
            heldKey: heldKey,
            outcome: outcome,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        ))
    }

    /// Space or Tab tapped on its own while it doubles as a modifier layer.
    func reportTap(keyCode: UInt16, characters: String) {
        currentSink()?(KeystrokeEvent(
            input: .key(keyCode: keyCode, characters: characters), modifiers: [], outcome: .passedThrough
        ))
    }

    func reportMouse(button: Int, modifiers: CGEventFlags, outcome: KeystrokeEvent.Outcome) {
        currentSink()?(KeystrokeEvent(input: .mouse(button: button), modifiers: modifiers, outcome: outcome))
    }

    private func currentSink() -> (@Sendable (KeystrokeEvent) -> Void)? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return sink
    }

    /// What the key types under the active layout, e.g. "й" for the Q key.
    private static func characters(of event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer
        )
        return String(utf16CodeUnits: buffer, count: length)
    }
}
