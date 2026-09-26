import Foundation
import UserNotifications

// Stateless pieces of the picker flow, kept out of PickerCoordinator.swift so the
// coordinator stays focused on its own state.

// MARK: - Query options

/// How one `PickerCoordinator.runQuery` call differs from the others. The four
/// entry points (debounced typing, initial load, refresh-in-place, dynamic
/// refresh) each use one of the presets below. A preset changes how fresh the
/// inputs are, never what is ranked: every run scores the search field's text,
/// with the same keyboard-layout fallback, because whichever run claims the
/// newest generation is the one left on screen.
struct QueryOptions {
    /// Capture a fresh `SystemContext` and refresh the theme first.
    var captureContext: Bool
    /// Re-fetch the catalog corpus from modules instead of reusing the cached one.
    /// Keystrokes pass `false`; show/refresh paths pass `true`.
    var refreshCorpus: Bool
    /// Keep the current selection across the list update.
    var preservingSelection = true
    /// Set `isLoading = false` when finished.
    var clearsLoading: Bool
    /// Refresh the empty-query cache when the query is empty.
    var updatesEmptyCacheWhenEmpty: Bool

    /// Debounced typing. Context is captured lazily, on the first query of a session.
    static func keystroke(captureContext: Bool) -> QueryOptions {
        QueryOptions(
            captureContext: captureContext,
            refreshCorpus: false,
            clearsLoading: true,
            updatesEmptyCacheWhenEmpty: false
        )
    }

    /// Panel just shown: fresh context and corpus. Fills the empty-query cache
    /// unless the field already holds text.
    static let initialLoad = QueryOptions(
        captureContext: true,
        refreshCorpus: true,
        clearsLoading: true,
        updatesEmptyCacheWhenEmpty: true
    )

    /// Re-shown with retained state: re-scores without clearing the list.
    static let refreshInPlace = QueryOptions(
        captureContext: true,
        refreshCorpus: true,
        clearsLoading: false,
        updatesEmptyCacheWhenEmpty: true
    )

    /// A module reported new actions while the picker is open.
    static let dynamicRefresh = QueryOptions(
        captureContext: false,
        refreshCorpus: true,
        clearsLoading: false,
        updatesEmptyCacheWhenEmpty: false
    )
}

// MARK: - Parameter input

extension ActionParameter {
    /// The value pressing Return confirms for this parameter, or nil when there's
    /// nothing valid to confirm yet. `typed` is the trimmed parameter query.
    func confirmableValue(typed: String, selectedOptionID: String?) -> String? {
        switch type {
        case .selection, .dynamicSelection, .toggle:
            return selectedOptionID
        case .text, .path:
            return typed.isEmpty && isRequired ? nil : typed
        case let .number(min, max):
            guard let number = Double(typed) else { return nil }
            if let min, number < min { return nil }
            if let max, number > max { return nil }
            return typed
        }
    }
}

extension [ParameterOption] {
    /// Options that fuzzy-match `query`, best match first, with label highlights set.
    func fuzzyFiltered(by query: String) -> [ParameterOption] {
        var scored: [(option: ParameterOption, score: Double)] = []
        for option in self {
            guard let result = FuzzyMatcher.match(query: query, against: option.label) else { continue }
            var opt = option
            opt.labelHighlightRanges = result.matchedRanges.isEmpty ? nil : result.matchedRanges
            scored.append((option: opt, score: result.score))
        }
        scored.sort { $0.score > $1.score }
        return scored.map(\.option)
    }
}

// MARK: - Action results

extension ActionItem {
    /// A row for an action pushed by another action's `.pushActions` result. Pushed
    /// lists aren't fuzzy-scored, so the action's own relevance is its score.
    init(pushed action: any Action) {
        self.init(
            id: action.id,
            title: action.title,
            subtitle: action.subtitle,
            iconSystemName: action.iconName,
            appIconPath: action.appIconPath,
            score: action.relevanceScore,
            moduleID: action.id.moduleID,
            hasParameters: !action.parameters.filter(\.isRequired).isEmpty,
            keywords: action.keywords
        )
    }
}

func postActionNotification(title: String, body: String) {
    Task {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "vibeshed.action.result.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.delegate = ForegroundNotificationPresenter.shared
        do {
            // Only prompts while permission is undetermined; afterwards it just reports the
            // stored answer. Without it, results posted before anything else (e.g. the timer
            // module) asked for permission are silently dropped.
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                Log.picker.warning("Not posting notification: permission denied")
                return
            }
            try await center.add(request)
        } catch {
            Log.picker.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Shows banners even while Vibeshed is the active app — it usually still is right
/// after the picker hides, and macOS suppresses foreground notifications by default.
/// Held as a singleton because `UNUserNotificationCenter.delegate` is weak.
private final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = ForegroundNotificationPresenter()

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
