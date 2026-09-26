import IOKit
import IOKit.hid

/// The system-wide CapsLock toggle (what the LED shows and what apps like UTM
/// sync a guest to). Suppressing the capslock flagsChanged event in the tap
/// does not stop the HID system from flipping this, so using capslock as a
/// modifier leaves it in whatever state the last press happened to leave it.
enum SystemCapsLock {
    private static let connection: io_connect_t? = {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        var connect: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect)
        guard result == KERN_SUCCESS else {
            Log.keybindings.error("SystemCapsLock: IOServiceOpen failed (\(result, privacy: .public))")
            return nil
        }
        return connect
    }()

    /// Clears the toggle if it is on. Setting it posts its own flagsChanged,
    /// so the read-first guard keeps that echo from looping back here.
    static func turnOff() {
        guard let connection else { return }
        var isOn = false
        guard IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &isOn) == KERN_SUCCESS,
              isOn
        else { return }
        IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false)
    }
}
