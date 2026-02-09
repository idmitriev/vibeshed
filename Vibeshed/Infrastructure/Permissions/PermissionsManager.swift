import AppKit
import ApplicationServices

@MainActor
@Observable
final class PermissionsManager {
    private(set) var hasAccessibility: Bool = false
    private(set) var hasScreenRecording: Bool = false

    func checkPermissions() {
        hasAccessibility = checkAccessibility(prompt: false)
        hasScreenRecording = checkScreenRecording()
        Log.permissions.info(
            "Permissions: accessibility=\(self.hasAccessibility), screenRecording=\(self.hasScreenRecording)"
        )
    }

    func requestAccessibility() {
        hasAccessibility = checkAccessibility(prompt: true)
    }

    private func checkAccessibility(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue(): prompt
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
                  let name = info[kCGWindowName as String] as? String else {
                return false
            }
            return !name.isEmpty
        }
    }
}
