import AppKit
import ApplicationServices

@MainActor
@Observable
final class PermissionsManager {
    private(set) var statuses: [Permission: Bool] = [:]

    private let eventBus: EventBus
    private var recheckTimer: DispatchSourceTimer?
    private let recheckInterval: TimeInterval = 10

    init(eventBus: EventBus) {
        self.eventBus = eventBus
        for permission in Permission.allCases {
            statuses[permission] = false
        }
    }

    // MARK: - Public API

    func checkAll() {
        for permission in Permission.allCases {
            let granted = check(permission)
            updateStatus(permission, granted: granted)
        }
        Log.permissions.info("Permissions: \(self.statusSummary)")
    }

    func isGranted(_ permission: Permission) -> Bool {
        statuses[permission] ?? false
    }

    func missingPermissions(from required: Set<Permission>) -> Set<Permission> {
        required.filter { !isGranted($0) }
    }

    func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            let granted = checkAccessibility(prompt: true)
            updateStatus(permission, granted: granted)
        case .screenRecording, .automation, .inputMonitoring, .fullDiskAccess:
            if let url = permission.systemSettingsURL {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func startPeriodicRecheck() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + recheckInterval, repeating: recheckInterval)
        timer.setEventHandler { [weak self] in
            self?.checkAll()
        }
        timer.resume()
        recheckTimer = timer
    }

    func stopPeriodicRecheck() {
        recheckTimer?.cancel()
        recheckTimer = nil
    }

    // MARK: - Per-Permission Checks

    private func check(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            return checkAccessibility(prompt: false)
        case .screenRecording:
            return checkScreenRecording()
        case .automation:
            return checkAutomation()
        case .inputMonitoring:
            return checkInputMonitoring()
        case .fullDiskAccess:
            return checkFullDiskAccess()
        }
    }

    private func checkAccessibility(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt,
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func checkScreenRecording() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return windowList.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  pid != currentPID,
                  let name = info[kCGWindowName as String] as? String
            else {
                return false
            }
            return !name.isEmpty
        }
    }

    private func checkAutomation() -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let aeDesc = target.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(
            aeDesc,
            typeWildCard,
            typeWildCard,
            false
        )
        return status == noErr
    }

    /// Probe automation permission for a specific app, optionally triggering the macOS consent dialog.
    /// Returns `.noErr` if allowed, `errAEEventNotPermitted` if denied, `procNotFound` if not running.
    @discardableResult
    func probeAutomation(for bundleID: String, prompt: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let aeDesc = target.aeDesc else { return OSStatus(errAEEventNotPermitted) }
        return AEDeterminePermissionToAutomateTarget(
            aeDesc,
            typeWildCard,
            typeWildCard,
            prompt
        )
    }

    private func checkInputMonitoring() -> Bool {
        CGPreflightListenEventAccess()
    }

    private func checkFullDiskAccess() -> Bool {
        let protectedPaths = [
            NSHomeDirectory() + "/Library/Mail",
            NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        return protectedPaths.contains { FileManager.default.isReadableFile(atPath: $0) }
    }

    // MARK: - Private Helpers

    private func updateStatus(_ permission: Permission, granted: Bool) {
        let previous = statuses[permission] ?? false
        statuses[permission] = granted
        if previous != granted {
            Log.permissions.info(
                "Permission \(permission.displayName) changed: \(previous) -> \(granted)"
            )
            Task {
                await eventBus.publish(.permissionChanged(permission, granted: granted))
            }
        }
    }

    private var statusSummary: String {
        Permission.allCases.map { p in
            "\(p.rawValue)=\(statuses[p] ?? false)"
        }.joined(separator: ", ")
    }
}
