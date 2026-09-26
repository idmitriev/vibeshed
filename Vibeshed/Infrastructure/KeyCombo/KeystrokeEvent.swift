import CoreGraphics

/// One input the event tap saw, reported to the keystroke visualizer. Built on
/// the tap thread, so it carries plain values only — never the `CGEvent`.
struct KeystrokeEvent: Sendable, Equatable {
    enum Input: Sendable, Equatable {
        /// `characters` is what the key types under the active layout (may be empty).
        case key(keyCode: UInt16, characters: String)
        /// CGEvent button number: 0 = left … 3 = back, 4 = forward.
        case mouse(button: Int)
    }

    /// A key held as a Vibeshed modifier layer (`capslock+h`, `space+j`, `tab+k`).
    enum HeldKey: Sendable, Equatable {
        case capsLock
        case space
        case tab
    }

    /// What Vibeshed did with the input.
    enum Outcome: Sendable, Equatable {
        case passedThrough
        case binding(ActionID)
        /// The chord Vibeshed sent instead.
        case remap(RemapTarget)
    }

    static let chordModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    let input: Input
    /// Only `chordModifiers`.
    let modifiers: CGEventFlags
    var heldKey: HeldKey?
    let outcome: Outcome
    var isRepeat = false
}
