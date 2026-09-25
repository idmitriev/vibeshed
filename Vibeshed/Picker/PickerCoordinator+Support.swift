import Foundation
import UserNotifications

// Stateless pieces of the picker flow, kept out of PickerCoordinator.swift so the
// coordinator stays focused on its own state.

// MARK: - Query options

/// How one `PickerCoordinator.runQuery` call differs from the others. The four
/// entry points (debounced typing, initial load, refresh-in-place, dynamic
/// refresh) each use one of the presets below.
struct QueryOptions {
    /// Capture a fresh `SystemContext` and refresh the theme first.
    var captureContext: Bool
    /// Re-fetch the catalog corpus from modules instead of reusing the cached one.
    /// Keystrokes pass `false`; show/refresh paths pass `true`.
    var refreshCorpus: Bool
    /// Keep the current selection across the list update.
    var preservingSelection = true
    /// On empty results, retry via keyboard transliteration.
    var layoutCorrectionFallback: Bool
    /// Set `isLoading = false` when finished.
    var clearsLoading: Bool
    /// Refresh the empty-query cache when the query is empty.
    var updatesEmptyCacheWhenEmpty: Bool

    /// Debounced typing. Context is captured lazily, on the first query of a session.
    static func keystroke(captureContext: Bool) -> QueryOptions {
        QueryOptions(
            captureContext: captureContext,
            refreshCorpus: false,
            layoutCorrectionFallback: true,
            clearsLoading: true,
            updatesEmptyCacheWhenEmpty: false
        )
    }

    /// Panel just shown: fresh context and corpus, fills the empty-query cache.
    static let initialLoad = QueryOptions(
        captureContext: true,
        refreshCorpus: true,
        layoutCorrectionFallback: false,
        clearsLoading: true,
        updatesEmptyCacheWhenEmpty: true
    )

    /// Re-shown with retained state: re-scores without clearing the list.
    static let refreshInPlace = QueryOptions(
        captureContext: true,
        refreshCorpus: true,
        layoutCorrectionFallback: false,
        clearsLoading: false,
        updatesEmptyCacheWhenEmpty: true
    )

    /// A module reported new actions while the picker is open.
    static let dynamicRefresh = QueryOptions(
        captureContext: false,
        refreshCorpus: true,
        layoutCorrectionFallback: true,
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
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
        identifier: "vibeshed.action.result.\(UUID().uuidString)",
        content: content,
        trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
        if let error {
            Log.picker.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
        }
    }
}
