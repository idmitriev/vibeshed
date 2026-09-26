import Foundation
import IOKit
import IOKit.hid

/// Monitors the physical press/release state of CapsLock using IOKit HID.
/// CGEvent flagsChanged is unreliable for capslock when the key is remapped
/// at the system level; IOKit HID reads the raw hardware state directly.
final class CapsLockMonitor: @unchecked Sendable {
    static let shared = CapsLockMonitor()
    static let stateChanged = Notification.Name("CapsLockMonitorStateChanged")

    private var hidManager: IOHIDManager?
    private var _isPressed = false
    /// Which of `capsLockUsages` are down. HID callback (main run loop) only.
    private var pressedUsages: Set<UInt32> = []
    private let lock = NSLock()

    /// Keyboard page 0x07 usages that count as capslock: CapsLock itself (0x39)
    /// and F18 (0x6D), which is what CapsLockForwarder on a host Vibeshed sends
    /// into a VM in place of a held capslock.
    private let capsLockUsages: Set<UInt32> = [0x39, 0x6D]

    var isPressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isPressed
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
        _isPressed = false
        lock.unlock()
        pressedUsages = []

        Log.keybindings.info("CapsLockMonitor stopped")
    }

    private func handleHIDValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        guard usagePage == kHIDPage_KeyboardOrKeypad else { return }
        guard capsLockUsages.contains(usage) else { return }

        if IOHIDValueGetIntegerValue(value) != 0 {
            pressedUsages.insert(usage)
        } else {
            pressedUsages.remove(usage)
        }
        let pressed = !pressedUsages.isEmpty

        lock.lock()
        let wasPressed = _isPressed
        _isPressed = pressed
        lock.unlock()

        if pressed != wasPressed {
            Log.keybindings.info(
                "CapsLock HID: \(pressed ? "DOWN" : "UP", privacy: .public)"
            )
            NotificationCenter.default.post(name: Self.stateChanged, object: nil)
        }
    }
}
