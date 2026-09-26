import CoreGraphics

extension EventTapHandler {
    /// Marker value set on `eventSourceUserData` so the tap recognises
    /// injected events and passes them through untouched.
    static let injectedMarker: Int64 = 0x5649_4245 // "VIBE"

    func isInjected(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == Self.injectedMarker
    }

    func injectKeyPress(keyCode: UInt16, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        {
            down.flags = modifiers
            up.flags = modifiers
            down.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
            up.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
            down.post(tap: .cgSessionEventTap)
            up.post(tap: .cgSessionEventTap)
        }
    }
}
