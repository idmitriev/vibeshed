import Foundation
import os

/// Bundle IDs whose events the tap forwards untouched. Written from the main
/// actor on config reload, read from the tap callback thread on every event.
final class AppExclusionList: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var bundleIDs: Set<String> = []
    /// Last app an exclusion was logged for, so entering an excluded app logs
    /// once rather than on every event. Tap callback thread only.
    private var lastLogged: String?

    func update(_ newValue: Set<String>) {
        let folded = Set(newValue.map { $0.lowercased() })
        os_unfair_lock_lock(&lock)
        bundleIDs = folded
        os_unfair_lock_unlock(&lock)
        guard !folded.isEmpty else { return }
        let list = folded.sorted().joined(separator: ", ")
        Log.keybindings.info("Keybindings disabled in: \(list, privacy: .public)")
    }

    /// Side-effect-free check for use off the tap thread. `focusedApp` must
    /// already be lowercased.
    func contains(_ focusedApp: String) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return bundleIDs.contains(focusedApp)
    }

    /// `focusedApp` must already be lowercased.
    func excludes(_ focusedApp: String) -> Bool {
        os_unfair_lock_lock(&lock)
        let matched = bundleIDs.contains(focusedApp)
        os_unfair_lock_unlock(&lock)

        guard matched else {
            lastLogged = nil
            return false
        }
        if lastLogged != focusedApp {
            lastLogged = focusedApp
            Log.keybindings.info(
                "Passing input through — keybindings disabled for \(focusedApp, privacy: .public)"
            )
        }
        return true
    }
}
