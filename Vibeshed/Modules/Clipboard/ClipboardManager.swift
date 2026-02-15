import AppKit
import Foundation
import OSLog

private let log = Log.module("clipboard")

enum ClipboardManager {
    /// Token returned from `startMonitoring` to control the polling timer.
    final class MonitorToken: @unchecked Sendable {
        fileprivate var timer: Timer?

        func invalidate() {
            timer?.invalidate()
            timer = nil
        }

        deinit {
            timer?.invalidate()
        }
    }

    /// Starts polling `NSPasteboard.general.changeCount` at the given interval.
    /// Calls `onChange` with `(content, sourceAppName)` when new string content is detected.
    @MainActor
    static func startMonitoring(
        interval: TimeInterval,
        onChange: @escaping (String, String?) -> Void
    ) -> MonitorToken {
        let token = MonitorToken()
        var lastChangeCount = NSPasteboard.general.changeCount

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            let currentCount = NSPasteboard.general.changeCount
            guard currentCount != lastChangeCount else { return }
            lastChangeCount = currentCount

            guard let content = NSPasteboard.general.string(forType: .string),
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }

            let sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
            onChange(content, sourceApp)
        }
        token.timer = timer
        return token
    }

    // MARK: - Pasteboard Operations

    @MainActor
    static func writeToPasteboard(_ content: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    @MainActor
    static func pasteFromPasteboard() {
        // keyCode 9 = 'v'
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        else {
            log.error("Failed to create CGEvent for paste simulation")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
