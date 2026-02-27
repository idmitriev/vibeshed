import AppKit
import ApplicationServices
import EventKit

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
        Log.permissions.info("Permissions: \(self.statusSummary, privacy: .public)")
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
        case .inputMonitoring:
            let granted = CGRequestListenEventAccess()
            updateStatus(permission, granted: granted)
        case .screenRecording, .automation, .fullDiskAccess:
            if let url = permission.systemSettingsURL {
                NSWorkspace.shared.open(url)
            }
        case .calendars:
            let store = EKEventStore()
            Task {
                do {
                    let granted = try await store.requestFullAccessToEvents()
                    self.updateStatus(permission, granted: granted)
                } catch {
                    if let url = permission.systemSettingsURL {
                        NSWorkspace.shared.open(url)
                    }
                }
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
        case .calendars:
            return checkCalendars()
        }
    }

    private func checkAccessibility(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt,
        ] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            return true
        }
        // AXIsProcessTrustedWithOptions can return false for unsigned
        // debug builds even when the permission is actually granted.
        // Fall back to CGPreflightPostEventAccess which reflects the
        // real runtime capability.
        return CGPreflightPostEventAccess()
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
        // CGPreflightListenEventAccess checks the CGEvent listen
        // capability without prompting.  IOKit HID (used by
        // CapsLockMonitor) may require a broader Input Monitoring
        // grant, but probing IOKit on every recheck is expensive
        // and can show duplicate dialogs.  We rely on the CGEvent
        // check here and let CapsLockMonitor.start() surface the
        // IOKit-specific failure at runtime.
        CGPreflightListenEventAccess()
    }

    private func checkCalendars() -> Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
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
                "Permission \(permission.displayName, privacy: .public) changed: \(previous, privacy: .public) -> \(granted, privacy: .public)"
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
