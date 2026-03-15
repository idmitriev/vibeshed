import Foundation

enum ContextualScorer {
    /// Compute an additive score boost for an action based on system context.
    /// Returns a value in [-0.15, +0.15] that is added to the FuzzyMatcher score.
    static func boost(
        actionID: ActionID,
        moduleID: String,
        context: SystemContext
    ) -> Double {
        var total = 0.0
        total += focusedAppBoost(moduleID: moduleID, actionID: actionID, context: context)
        total += runningStateBoost(moduleID: moduleID, actionID: actionID, context: context)
        total += timeBoost(moduleID: moduleID, actionID: actionID, context: context)
        total += audioBoost(actionID: actionID, context: context)
        total += windowCountBoost(actionID: actionID, context: context)
        return max(-0.15, min(0.15, total))
    }

    // MARK: - Focused App

    private static let browserBundleIDs: Set<String> = Set(
        BrowserRegistry.all.map(\.bundleID)
    )

    private static let vscodeBundleIDPrefixes = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf",        // Windsurf
    ]

    private static func focusedAppBoost(
        moduleID: String,
        actionID: ActionID,
        context: SystemContext
    ) -> Double {
        guard let bundleID = context.focusedAppBundleID else { return 0 }

        // Boost module matching the focused app
        if browserBundleIDs.contains(bundleID), moduleID == "browser" {
            return 0.10
        }
        if bundleID == "com.googlecode.iterm2", moduleID == "iterm" {
            return 0.10
        }
        if isVSCodeVariant(bundleID), moduleID == "vscode" {
            return 0.08
        }
        if bundleID == "com.spotify.client", moduleID == "spotify" {
            return 0.10
        }
        if bundleID == "ru.keepcoder.Telegram", moduleID == "telegram" {
            return 0.08
        }

        // Demote the focused app's own application action (user likely wants something else)
        if moduleID == "application" {
            let actionRaw = actionID.rawValue
            if actionRaw.hasPrefix("application/app.") {
                let appID = String(actionRaw.dropFirst("application/app.".count))
                if appID == bundleID {
                    return -0.05
                }
            }
        }

        return 0
    }

    private static func isVSCodeVariant(_ bundleID: String) -> Bool {
        vscodeBundleIDPrefixes.contains { bundleID.hasPrefix($0) }
    }

    // MARK: - Running State

    private static let spotifyPlaybackActions: Set<String> = [
        "spotify/playPause",
        "spotify/next",
        "spotify/previous",
        "spotify/nowPlaying",
    ]

    private static func runningStateBoost(
        moduleID: String,
        actionID: ActionID,
        context: SystemContext
    ) -> Double {
        guard moduleID == "spotify" else { return 0 }

        if context.isSpotifyRunning {
            if spotifyPlaybackActions.contains(actionID.rawValue) {
                return 0.05
            }
        } else {
            return -0.05
        }
        return 0
    }

    // MARK: - Time of Day

    private static let lateNightActions: Set<String> = [
        "system/lock",
        "system/sleep",
    ]

    private static func timeBoost(
        moduleID: String,
        actionID: ActionID,
        context: SystemContext
    ) -> Double {
        var boost = 0.0

        // Late night: boost lock/sleep
        if context.hour >= 22 || context.hour < 6 {
            if lateNightActions.contains(actionID.rawValue) {
                boost += 0.08
            }
        }

        // Business hours on weekdays: boost github
        if !context.isWeekend, context.hour >= 9, context.hour < 17 {
            if moduleID == "github" {
                boost += 0.03
            }
        }

        return boost
    }

    // MARK: - Audio State

    private static func audioBoost(
        actionID: ActionID,
        context: SystemContext
    ) -> Double {
        let raw = actionID.rawValue
        guard raw.hasPrefix("audio/") else { return 0 }

        let name = String(raw.dropFirst("audio/".count))

        if context.isOutputMuted {
            // When muted, boost unmute and volume-up actions
            if name == "mute" || name.hasPrefix("volume") && !name.hasSuffix("Down") {
                return 0.08
            }
        } else if context.outputVolume > 0.8 {
            // Volume is high, boost mute
            if name == "mute" {
                return 0.05
            }
        } else if context.outputVolume == 0 {
            // Volume is zero but not muted, boost volume set actions
            if name.hasPrefix("volume") && !name.hasSuffix("Down") {
                return 0.06
            }
        }

        return 0
    }

    // MARK: - Window Count

    private static let tilingActions: Set<String> = [
        "window/tileLeft",
        "window/tileRight",
        "window/tileTop",
        "window/tileBottom",
    ]

    private static let singleWindowActions: Set<String> = [
        "window/maximize",
        "window/center",
    ]

    private static func windowCountBoost(
        actionID: ActionID,
        context: SystemContext
    ) -> Double {
        let raw = actionID.rawValue

        if context.visibleWindowCount > 3 {
            if tilingActions.contains(raw) {
                return 0.05
            }
        } else if context.visibleWindowCount <= 1 {
            if singleWindowActions.contains(raw) {
                return 0.05
            }
        }

        return 0
    }
}
