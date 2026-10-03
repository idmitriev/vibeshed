import AppKit
import ApplicationServices
import EventKit

@MainActor
@Observable
final class PermissionsManager {
    private(set) var statuses: [Permission: Bool] = [:]
    /// What macOS last said about Vibeshed controlling each app, by bundle ID. An app
    /// that has quit keeps its last answer: macOS only answers for running apps, and
    /// System Events quits when idle.
    private(set) var automationStatuses: [String: AutomationConsent.Status] = [:]

    private let eventBus: EventBus
    private var recheckTask: Task<Void, Never>?
    private let recheckInterval: Duration = .seconds(10)

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

    /// Re-reads one permission now rather than at the next periodic recheck.
    func refresh(_ permission: Permission) {
        updateStatus(permission, granted: check(permission))
    }

    func openSettings(for permission: Permission) {
        if let url = permission.systemSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks macOS for `permission`. Where macOS has a prompt it shows it (once; later
    /// calls return quietly) and lists Vibeshed in that Privacy & Security pane, so
    /// granting is a single switch there; Full Disk Access has no prompt, so its pane
    /// opens. Returns once the request is out, except for the dialogs macOS answers in
    /// place — Automation (for System Events) and Calendars — which it waits on.
    func request(_ permission: Permission) async {
        switch permission {
        case .accessibility:
            updateStatus(permission, granted: checkAccessibility(prompt: true))
        case .inputMonitoring:
            updateStatus(permission, granted: CGRequestListenEventAccess())
        case .screenRecording:
            updateStatus(permission, granted: CGRequestScreenCaptureAccess() || checkScreenRecording())
        case .automation:
            await requestAutomation(for: [AutomationConsent.systemEvents])
        case .fullDiskAccess:
            openSettings(for: permission)
        case .calendars:
            let store = EKEventStore()
            do {
                let granted = try await store.requestFullAccessToEvents()
                updateStatus(permission, granted: granted)
            } catch {
                openSettings(for: permission)
            }
        }
    }

    /// Asks macOS about each app, one dialog at a time (see `AutomationConsent.ask`).
    @discardableResult
    func requestAutomation(for bundleIDs: [String]) async -> [String: AutomationConsent.Status] {
        let answers = await AutomationConsent.ask(for: bundleIDs)
        for (bundleID, status) in answers {
            record(status, for: bundleID)
        }
        refresh(.automation)
        return answers
    }

    /// Re-reads where Automation stands for each app, without asking.
    func refreshAutomation(for bundleIDs: [String]) {
        for bundleID in bundleIDs {
            record(AutomationConsent.status(for: bundleID), for: bundleID)
        }
        refresh(.automation)
    }

    /// A running app's answer replaces what was known; "not running" adds nothing new.
    private func record(_ status: AutomationConsent.Status, for bundleID: String) {
        guard status != .notRunning || automationStatuses[bundleID] == nil else { return }
        automationStatuses[bundleID] = status
    }

    func startPeriodicRecheck() {
        recheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.recheckInterval ?? .seconds(10))
                guard !Task.isCancelled else { break }
                self?.checkAll()
            }
        }
    }

    func stopPeriodicRecheck() {
        recheckTask?.cancel()
        recheckTask = nil
    }

    // MARK: - Per-Permission Checks

    private func check(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            checkAccessibility(prompt: false)
        case .screenRecording:
            checkScreenRecording()
        case .automation:
            checkAutomation()
        case .inputMonitoring:
            checkInputMonitoring()
        case .fullDiskAccess:
            checkFullDiskAccess()
        case .calendars:
            checkCalendars()
        }
    }

    private func checkAccessibility(prompt: Bool) -> Bool {
        // `kAXTrustedCheckOptionPrompt` imports as a global `var`, which Swift 6
        // rejects as shared mutable state. Its value is a stable documented
        // constant, so spell it out rather than reading the global.
        let options = [
            "AXTrustedCheckOptionPrompt" as CFString: prompt,
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

    /// macOS's own answer, or else other apps' window titles showing up, which
    /// CGWindowList only reveals with the permission. That second signal needs a titled
    /// window on screen, so it can't be the only one: on an empty desktop a grant would
    /// never be noticed.
    private func checkScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess() || otherAppsWindowTitlesVisible()
    }

    private func otherAppsWindowTitlesVisible() -> Bool {
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

    /// Stands for Automation as a whole: System Events is what the built-in modules
    /// script. Permission setup goes by each app in its plan instead (see
    /// `PermissionWalkthrough.automationHoldouts`).
    private func checkAutomation() -> Bool {
        let systemEvents = AutomationConsent.systemEvents
        record(AutomationConsent.status(for: systemEvents), for: systemEvents)
        return automationStatuses[systemEvents] == .allowed
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
            let change = "\(previous) -> \(granted)"
            Log.permissions.info(
                "Permission \(permission.displayName, privacy: .public) changed: \(change, privacy: .public)"
            )
            Task {
                await eventBus.publish(.permissionChanged(permission, granted: granted))
            }
        }
    }

    private var statusSummary: String {
        Permission.allCases.map { permission in
            "\(permission.rawValue)=\(statuses[permission] ?? false)"
        }.joined(separator: ", ")
    }
}
