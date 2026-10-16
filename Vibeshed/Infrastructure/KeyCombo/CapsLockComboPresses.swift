/// Keys whose current press fired a capslock combo. A press belongs to whoever
/// got its first keyDown, through the autorepeats to the keyUp:
/// - The app never saw a combo key go down, so it mustn't see the key's repeats
///   (after capslock is let go first) or its release either.
/// - A press the app did see stays the app's: capslock going down mid-hold
///   doesn't turn its repeats into combos. Otherwise the combo moves focus
///   (say to the picker) and the keyUp goes there, so the app is left with a
///   key it thinks is still held — YouTube keeps playing at 2x for a held Space.
///
/// Tap callback thread only.
struct CapsLockComboPresses {
    enum Outcome: Equatable {
        /// Run the combo's action and keep the key from the app.
        case fire
        /// Keep the key from the app without running anything.
        case swallow
        /// Not a combo: handle the key as usual.
        case pass
    }

    private var keys: Set<UInt16> = []

    /// - Parameter comboIsHeld: capslock is down and the key is bound to an
    ///   action in the focused app.
    mutating func keyDown(_ keyCode: UInt16, isRepeat: Bool, comboIsHeld: Bool) -> Outcome {
        if isRepeat {
            guard keys.contains(keyCode) else { return .pass }
            // Holding the combo repeats it (capslock+minus keeps shrinking a
            // window); once capslock is up the key stays quiet until released.
            return comboIsHeld ? .fire : .swallow
        }
        // A new press. Also drops what's left of an old one whose keyUp the
        // tap missed, so this press's keyUp isn't swallowed by mistake.
        keys.remove(keyCode)
        guard comboIsHeld else { return .pass }
        keys.insert(keyCode)
        return .fire
    }

    /// True when the keyUp ends a combo press, so the app shouldn't get it.
    mutating func keyUp(_ keyCode: UInt16) -> Bool {
        keys.remove(keyCode) != nil
    }
}
