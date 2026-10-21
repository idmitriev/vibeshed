import IOKit
import IOKit.hid

/// The VM's CapsLock toggle. UTM mirrors the host's toggle into the guest, so
/// a host that left it on puts macOS's caps-lock badge under every text field
/// on camera; takes switch it off before each step.
enum CapsLock {
    private static let connection: io_connect_t? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect) == KERN_SUCCESS
        else { return nil }
        return connect
    }()

    static func turnOff() {
        guard let connection else { return }
        var isOn = false
        guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &isOn) == KERN_SUCCESS, isOn
        else { return }
        IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false)
    }
}
