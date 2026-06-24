import AppKit
import Foundation
import OSLog

enum SettingsManager {
    private static let log = Log.module("settings")

    /// Opens a System Settings pane via its `x-apple.systempreferences:` URL.
    static func open(_ pane: SettingsPane) {
        guard let url = URL(string: pane.urlString) else {
            log.error("Invalid settings URL: \(pane.urlString, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }
}
