import Foundation
import IOKit
import IOKit.hid

/// Monitors the physical press/release state of CapsLock using IOKit HID.
/// CGEvent flagsChanged is unreliable for capslock when the key is remapped
/// at the system level; IOKit HID reads the raw hardware state directly.
///
/// Also counts a capslock hold forwarded from a host Vibeshed as F18 (see
/// CapsLockForwarder). That arrives through a VM's virtual keyboard, which
/// IOKit HID clients don't see, so the event tap reports it instead.
final class CapsLockMonitor: @unchecked Sendable {
    static let shared = CapsLockMonitor()
    static let stateChanged = Notification.Name("CapsLockMonitorStateChanged")

    private var hidManager: IOHIDManager?
    // Guarded by `lock`
    private var hidPressed = false
    private var forwardedPressed = false
    private let lock = NSLock()

    /// HID usage code for CapsLock (keyboard page 0x07, usage 0x39 = 57)
    private let capsLockHIDUsage: UInt32 = 0x39

    var isPressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hidPressed || forwardedPressed
    }

    /// Called from the event tap on a forwarded F18 down/up. Takes effect before
    /// the tap sees the next key, so a combo typed right after still matches.
    func setForwardedPressed(_ pressed: Bool) {
        update { $0.forwardedPressed = pressed }
    }

    private init() {}

    /// Attempts to start monitoring. Returns `true` on success.
    @discardableResult
    func start() -> Bool {
        guard hidManager == nil else { return true }

        let manager = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        hidManager = manager

        // Match keyboard devices only
        let matchingDict: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Keyboard,
        ]
        IOHIDManagerSetDeviceMatching(manager, matchingDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(
            manager,
            { ctx, _, _, value in
                guard let ctx else { return }
                let monitor = Unmanaged<CapsLockMonitor>
                    .fromOpaque(ctx).takeUnretainedValue()
                monitor.handleHIDValue(value)
            },
            context
        )

        IOHIDManagerScheduleWithRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )

        let result = IOHIDManagerOpen(
            manager,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        if result != kIOReturnSuccess {
            let desc = ioReturnDescription(result)
            Log.keybindings.error(
                "CapsLockMonitor: IOHIDManagerOpen failed: \(desc, privacy: .public) (\(result, privacy: .public))"
            )
            // Clean up — unschedule and discard the manager
            IOHIDManagerUnscheduleFromRunLoop(
                manager,
                CFRunLoopGetMain(),
                CFRunLoopMode.commonModes.rawValue
            )
            hidManager = nil
            return false
        }

        Log.keybindings.info("CapsLockMonitor started")
        return true
    }

    private func ioReturnDescription(_ code: IOReturn) -> String {
        switch code {
        case kIOReturnSuccess: "success"
        case kIOReturnNotPermitted: "kIOReturnNotPermitted — grant Input Monitoring"
        case kIOReturnNotPrivileged: "kIOReturnNotPrivileged"
        case kIOReturnBadArgument: "kIOReturnBadArgument"
        case kIOReturnExclusiveAccess: "kIOReturnExclusiveAccess"
        default: "unknown IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16))"
        }
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        guard let manager = hidManager else { return }

        IOHIDManagerUnscheduleFromRunLoop(
            manager,
            CFRunLoopGetMain(),
            CFRunLoopMode.commonModes.rawValue
        )
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil

        lock.lock()
        hidPressed = false
        forwardedPressed = false
        lock.unlock()

        Log.keybindings.info("CapsLockMonitor stopped")
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        guard usagePage == kHIDPage_KeyboardOrKeypad else { return }
        guard usage == capsLockHIDUsage else { return }

        let pressed = IOHIDValueGetIntegerValue(value) != 0
        update { $0.hidPressed = pressed }
    }

    /// Applies `change` under the lock and, if the combined state flipped,
    /// logs it and posts `stateChanged` on the main thread.
    private func update(_ change: (CapsLockMonitor) -> Void) {
        lock.lock()
        let wasPressed = hidPressed || forwardedPressed
        change(self)
        let pressed = hidPressed || forwardedPressed
        let source = forwardedPressed ? "forwarded F18" : "HID"
        lock.unlock()

        guard pressed != wasPressed else { return }
        Log.keybindings.info(
            "CapsLock: \(pressed ? "DOWN" : "UP", privacy: .public) (\(source, privacy: .public))"
        )
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.stateChanged, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.stateChanged, object: nil)
            }
        }
    }
}
