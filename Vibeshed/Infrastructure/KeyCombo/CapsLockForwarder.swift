import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

/// Virtualization.framework consoles (UTM's macOS VMs) never pass CapsLock to the
/// guest as a press and release — they only mirror the host's toggle — so a
/// Vibeshed inside the VM can't see capslock held. While an excluded app is
/// focused, the physical hold is forwarded as F18 instead, which CapsLockMonitor
/// on the other side counts as capslock.
final class CapsLockForwarder: @unchecked Sendable {
    static let keyCode = UInt16(kVK_F18)

    private let exclusions: AppExclusionList
    private let focusedAppTracker: FocusedAppTracker

    private var lock = os_unfair_lock()
    private var enabled = false

    // Main thread only (CapsLockMonitor posts from its main-run-loop HID callback)
    private var observer: NSObjectProtocol?
    private var isForwarding = false

    init(exclusions: AppExclusionList, focusedAppTracker: FocusedAppTracker) {
        self.exclusions = exclusions
        self.focusedAppTracker = focusedAppTracker
    }

    /// Only forward while capslock is bound: otherwise it's a plain CapsLock key
    /// and the excluded app should get it as one.
    func setEnabled(_ newValue: Bool) {
        os_unfair_lock_lock(&lock)
        enabled = newValue
        os_unfair_lock_unlock(&lock)
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: CapsLockMonitor.stateChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.capsLockStateChanged()
        }
    }

    func stop() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
        if isForwarding {
            isForwarding = false
            post(keyDown: false)
        }
    }

    private func capsLockStateChanged() {
        if CapsLockMonitor.shared.isPressed {
            os_unfair_lock_lock(&lock)
            let enabled = enabled
            os_unfair_lock_unlock(&lock)
            guard enabled, !isForwarding,
                  exclusions.contains(focusedAppTracker.focusedBundleIDLowercased)
            else { return }
            isForwarding = true
            post(keyDown: true)
        } else if isForwarding {
            // Released even if focus has since left the excluded app, so the
            // guest never sees F18 stuck down.
            isForwarding = false
            post(keyDown: false)
        }
    }

    private func post(keyDown: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: Self.keyCode, keyDown: keyDown)
        else { return }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: EventTapHandler.injectedMarker)
        event.post(tap: .cgSessionEventTap)
    }
}
