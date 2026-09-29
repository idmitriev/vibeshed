import AppKit
import ApplicationServices
import OSLog

private let log = Log.module("performance")

/// Opens Activity Monitor on a given tab. Activity Monitor reads its tab from its
/// `SelectedTab` preference at launch; once it's running, the tab is switched by pressing
/// the segment in its toolbar through Accessibility.
enum ActivityMonitor {
    /// Toolbar segments, in order. The raw value is the `SelectedTab` preference.
    enum Tab: Int, Sendable {
        case cpu = 0
        case memory = 1
        case energy = 2
        case disk = 3
        case network = 4

        /// The segment's accessibility description in English.
        var segmentDescription: String {
            switch self {
            case .cpu: "CPU"
            case .memory: "Memory"
            case .energy: "Energy"
            case .disk: "Disk"
            case .network: "Network"
            }
        }
    }

    static let bundleID = "com.apple.ActivityMonitor"

    private static let queue = DispatchQueue(label: "com.ivandmitriev.Vibeshed.activity-monitor", qos: .userInitiated)

    @MainActor
    static func open(tab: Tab?) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ActivityMonitorError.notInstalled
        }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        if let tab, !wasRunning {
            SystemPreferences.set(tab.rawValue, forKey: "SelectedTab", domain: bundleID)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // For a running app this is a reopen, which brings back a closed main window.
        let app = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)

        guard let tab, wasRunning else { return }
        guard AXIsProcessTrusted() else {
            log.info("Activity Monitor tab not switched: no Accessibility access")
            return
        }
        let pid = app.processIdentifier
        let pressed = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: pressSegment(for: tab, pid: pid)) }
        }
        if !pressed {
            let message = "Couldn't switch Activity Monitor to the \(tab.segmentDescription) tab"
            log.warning("\(message, privacy: .public)")
        }
    }

    // MARK: - Accessibility

    /// Waits up to `timeout` for the main window, since a reopened app may still be
    /// creating it. AX calls block on the target's main thread, hence the private queue.
    private static func pressSegment(for tab: Tab, pid: pid_t, timeout: TimeInterval = 2) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let segment = segment(for: tab, in: app) {
                return AXUIElementPerformAction(segment, kAXPressAction as CFString) == .success
            }
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private static func segment(for tab: Tab, in app: AXUIElement) -> AXUIElement? {
        for window in children(of: app, attribute: kAXWindowsAttribute) {
            guard let toolbar = children(of: window).first(where: { role(of: $0) == kAXToolbarRole }),
                  let group = firstDescendant(of: toolbar, role: kAXRadioGroupRole, depth: 3)
            else {
                continue
            }
            let segments = children(of: group)
            let wanted = tab.segmentDescription
            if let match = segments.first(where: { string(of: $0, attribute: kAXDescriptionAttribute) == wanted }) {
                return match
            }
            // Localized labels: fall back to the position, when every tab is there.
            if segments.count >= 5 {
                return segments[tab.rawValue]
            }
        }
        return nil
    }

    private static func firstDescendant(of element: AXUIElement, role wanted: String, depth: Int) -> AXUIElement? {
        for child in children(of: element) {
            if role(of: child) == wanted {
                return child
            }
            if depth > 0, let match = firstDescendant(of: child, role: wanted, depth: depth - 1) {
                return match
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement, attribute: String = kAXChildrenAttribute) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func role(of element: AXUIElement) -> String? {
        string(of: element, attribute: kAXRoleAttribute)
    }

    private static func string(of element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}

enum ActivityMonitorError: LocalizedError {
    case notInstalled

    var errorDescription: String? {
        "Activity Monitor isn't installed"
    }
}
