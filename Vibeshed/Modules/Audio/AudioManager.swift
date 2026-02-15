import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

private let log = Log.module("audio")

enum AudioManager {

    // MARK: - Output Volume

    static func getOutputVolume() -> Float {
        let deviceID = defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
        guard deviceID != kAudioObjectUnknown else {
            log.warning("getOutputVolume: no default output device")
            return 0
        }

        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume)
        guard status == noErr else {
            log.error("getOutputVolume: AudioObjectGetPropertyData failed (status \(status))")
            return 0
        }
        return volume
    }

    static func setOutputVolume(_ volume: Float) {
        let deviceID = defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
        guard deviceID != kAudioObjectUnknown else {
            log.warning("setOutputVolume: no default output device")
            return
        }

        var clamped = min(1.0, max(0.0, volume))
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let setStatus = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &clamped)
        if setStatus != noErr {
            log.error("setOutputVolume: AudioObjectSetPropertyData failed (status \(setStatus))")
        }
    }

    // MARK: - Output Mute

    static func isOutputMuted() -> Bool {
        getMute(
            device: defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice),
            scope: kAudioObjectPropertyScopeOutput
        )
    }

    static func setOutputMute(_ muted: Bool) {
        setMute(
            muted,
            device: defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice),
            scope: kAudioObjectPropertyScopeOutput
        )
    }

    static func toggleOutputMute() {
        setOutputMute(!isOutputMuted())
    }

    // MARK: - Input Mute

    static func isInputMuted() -> Bool {
        let deviceID = defaultDevice(for: kAudioHardwarePropertyDefaultInputDevice)
        guard deviceID != kAudioObjectUnknown else {
            log.warning("isInputMuted: no default input device")
            return false
        }
        guard hasMuteProperty(device: deviceID, scope: kAudioObjectPropertyScopeInput) else {
            return false
        }
        return getMute(device: deviceID, scope: kAudioObjectPropertyScopeInput)
    }

    static func setInputMute(_ muted: Bool) -> Bool {
        let deviceID = defaultDevice(for: kAudioHardwarePropertyDefaultInputDevice)
        guard deviceID != kAudioObjectUnknown else {
            log.warning("setInputMute: no default input device")
            return false
        }
        guard hasMuteProperty(device: deviceID, scope: kAudioObjectPropertyScopeInput) else {
            return false
        }
        setMute(muted, device: deviceID, scope: kAudioObjectPropertyScopeInput)
        return true
    }

    @discardableResult
    static func toggleInputMute() -> Bool {
        let deviceID = defaultDevice(for: kAudioHardwarePropertyDefaultInputDevice)
        guard deviceID != kAudioObjectUnknown else { return false }
        guard hasMuteProperty(device: deviceID, scope: kAudioObjectPropertyScopeInput) else {
            return false
        }
        let current = getMute(device: deviceID, scope: kAudioObjectPropertyScopeInput)
        setMute(!current, device: deviceID, scope: kAudioObjectPropertyScopeInput)
        return true
    }

    // MARK: - Device Listing

    struct AudioDevice: Sendable {
        let id: AudioDeviceID
        let name: String
    }

    static func outputDevices() -> [AudioDevice] {
        allDevices().filter { hasStreams(device: $0.id, scope: kAudioObjectPropertyScopeOutput) }
    }

    static func inputDevices() -> [AudioDevice] {
        allDevices().filter { hasStreams(device: $0.id, scope: kAudioObjectPropertyScopeInput) }
    }

    static func defaultOutputDeviceID() -> AudioDeviceID {
        defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func defaultInputDeviceID() -> AudioDeviceID {
        defaultDevice(for: kAudioHardwarePropertyDefaultInputDevice)
    }

    static func defaultOutputDeviceName() -> String {
        deviceName(defaultOutputDeviceID()) ?? "Unknown"
    }

    static func defaultInputDeviceName() -> String {
        deviceName(defaultInputDeviceID()) ?? "Unknown"
    }

    // MARK: - Device Selection

    static func setDefaultOutputDevice(_ deviceID: AudioDeviceID) {
        setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func setDefaultInputDevice(_ deviceID: AudioDeviceID) {
        setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    // MARK: - Media Keys

    static func playPause() {
        postMediaKey(keyType: 16) // NX_KEYTYPE_PLAY
    }

    static func nextTrack() {
        postMediaKey(keyType: 17) // NX_KEYTYPE_NEXT
    }

    static func previousTrack() {
        postMediaKey(keyType: 18) // NX_KEYTYPE_PREVIOUS
    }

    // MARK: - Private Helpers

    private static func defaultDevice(for selector: AudioObjectPropertySelector) -> AudioDeviceID {
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    private static func setDefaultDevice(
        _ deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) {
        var id = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, size, &id
        )
    }

    private static func getMute(device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        guard status == noErr else {
            log.error("getMute: AudioObjectGetPropertyData failed (status \(status))")
            return false
        }
        return muted != 0
    }

    private static func setMute(
        _ muted: Bool,
        device: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) {
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        let setStatus = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
        if setStatus != noErr {
            log.error("setMute: AudioObjectSetPropertyData failed (status \(setStatus))")
        }
    }

    private static func hasMuteProperty(
        device: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectHasProperty(device, &address)
    }

    private static func allDevices() -> [AudioDevice] {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size
        )
        guard status == noErr, size > 0 else {
            log.error("allDevices: failed to get device list size (status \(status))")
            return []
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceIDs
        )
        guard status == noErr else {
            log.error("allDevices: failed to get device IDs (status \(status))")
            return []
        }

        return deviceIDs.compactMap { id in
            guard let name = deviceName(id) else { return nil }
            return AudioDevice(id: id, name: name)
        }
    }

    private static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let cfName = name?.takeRetainedValue() else {
            if status != noErr {
                log.error("deviceName: failed for device \(deviceID) (status \(status))")
            }
            return nil
        }
        return cfName as String
    }

    private static func hasStreams(
        device: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) -> Bool {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        return status == noErr && size > 0
    }

    private static func postMediaKey(keyType: Int) {
        postMediaKeyEvent(keyType: keyType, keyDown: true)
        postMediaKeyEvent(keyType: keyType, keyDown: false)
    }

    private static func postMediaKeyEvent(keyType: Int, keyDown: Bool) {
        let flags = keyDown ? 0x0A00 : 0x0B00
        let data1 = (keyType << 16) | flags

        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: keyDown ? 0x000A00 : 0x000B00),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8, // NX_SUBTYPE_AUX_CONTROL_BUTTONS
            data1: data1,
            data2: -1
        )

        guard let event else {
            log.warning("postMediaKeyEvent: failed to create NSEvent for keyType \(keyType)")
            return
        }
        let cgEvent = event.cgEvent
        cgEvent?.post(tap: .cghidEventTap)
    }
}
