import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
@Observable
final class PickerState {
    var query: String = "" {
        didSet { querySubject.send(query) }
    }

    var actions: [ActionItem] = []
    var selectedActionID: ActionID?
    var isLoading: Bool = false

    /// Bumped whenever a list update snaps the selection back to the first row.
    /// The list view watches it to scroll back to the top — `selectedActionID`
    /// alone can't signal that, since the new first row may carry the same ID.
    private(set) var listResetToken: Int = 0

    /// Bumped when a refresh keeps the selected row but moves it, so the list view
    /// scrolls it back into view; its ID is unchanged, so no selection `onChange` fires.
    private(set) var selectionRevealToken: Int = 0

    /// The search text the rows on screen were ranked for. nil when they aren't a
    /// ranking of the field: the cached list shown at open, pushed rows, a message.
    @ObservationIgnored private(set) var listQuery: String?

    // MARK: - Mode state machine

    var mode: PickerMode = .search {
        didSet { onLivePreviewContextChange?() }
    }

    private var modeStack: [ModeStackEntry] = []

    /// Fired when anything a live parameter preview depends on changes (mode, highlighted
    /// option). The coordinator uses it to start, advance, or end the preview.
    @ObservationIgnored var onLivePreviewContextChange: (@MainActor () -> Void)?

    // MARK: - Parameter binding state

    var activeAction: (any Action)?
    var collectedValues: ParameterValues = [:]
    /// What the user picked or typed for each confirmed parameter, as shown (an option's
    /// label, not its ID). Defaults and skipped parameters have none.
    var collectedLabels: [String: String] = [:]
    var currentParameter: ActionParameter?
    var parameterOptions: [ParameterOption] = []
    var selectedParameterOptionID: String? {
        didSet { onLivePreviewContextChange?() }
    }

    var isLoadingOptions: Bool = false
    var layoutCorrectionHint: LayoutCorrectionHint?

    var parameterQuery: String = "" {
        didSet { parameterQuerySubject.send(parameterQuery) }
    }

    // MARK: - Action cache (not tracked by @Observable for perf)

    @ObservationIgnored var actionCache: [ActionID: any Action] = [:]

    // MARK: - Activation animation triggers

    /// Per-row activation counter. Each row reads its own counter; bumping the value
    /// retriggers the row's keyframe pulse animation.
    var activationCounters: [ActionID: Int] = [:]

    func bumpActivation(for id: ActionID) {
        activationCounters[id, default: 0] += 1
    }

    /// The same for parameter options, keyed by option ID.
    var optionActivationCounters: [String: Int] = [:]

    func bumpActivation(forOption id: String) {
        optionActivationCounters[id, default: 0] += 1
    }

    // MARK: - Publishers

    private let querySubject = PassthroughSubject<String, Never>()
    private let parameterQuerySubject = PassthroughSubject<String, Never>()

    /// No `removeDuplicates()`: its memory outlives a panel session and misses the
    /// runs that don't come from here (the initial load), so it could drop the field's
    /// text as a "repeat" while the list showed another text's results.
    /// `PickerCoordinator` skips repeats of what it last ranked instead.
    var debouncedQuery: AnyPublisher<String, Never> {
        querySubject
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }

    var debouncedParameterQuery: AnyPublisher<String, Never> {
        parameterQuerySubject
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - Reset

    func reset() {
        query = ""
        parameterQuery = ""
        actions = []
        selectedActionID = nil
        listResetToken = 0
        selectionRevealToken = 0
        listQuery = nil
        isLoading = false
        mode = .search
        modeStack = []
        activeAction = nil
        collectedValues = [:]
        collectedLabels = [:]
        currentParameter = nil
        parameterOptions = []
        selectedParameterOptionID = nil
        isLoadingOptions = false
        layoutCorrectionHint = nil
        actionCache = [:]
        activationCounters = [:]
        optionActivationCounters = [:]
    }

    /// Readies the picker for another run after one that kept it open (Shift held):
    /// clears what was typed and, in a parameter step, un-confirms that step's value
    /// so the next Return picks a new one. The mode and earlier steps' values stay
    /// as they were.
    func prepareForAnotherRun() {
        switch mode {
        case .search, .pushedActions:
            query = ""
        case .parameterInput:
            if let currentParameter {
                collectedValues[currentParameter.id] = nil
            }
            parameterQuery = ""
        }
    }

    // MARK: - Selection navigation

    func selectNext() {
        switch mode {
        case .search, .pushedActions:
            selectNextAction()
        case .parameterInput:
            selectNextParameterOption()
        }
    }

    func selectPrevious() {
        switch mode {
        case .search, .pushedActions:
            selectPreviousAction()
        case .parameterInput:
            selectPreviousParameterOption()
        }
    }

    // MARK: - Action list updates (with selection stability)

    /// Replaces the action list. `query` is the search text the rows were ranked for
    /// (nil for rows that aren't a ranking of the field).
    ///
    /// A list ranked for the same text as the one on screen is a refresh: a module
    /// reported new actions, or the picker came back with its state. Refreshes re-rank
    /// (the catalog fan-out answers in a different order each time, scores move with
    /// the clock), so the highlighted row stays highlighted wherever it lands, matched
    /// by ID; if it's gone, the row now in its place takes over. Anything else (new
    /// text, the first ranking after the cached list, pushed rows) starts on the first row.
    func updateActions(
        _ newActions: [ActionItem],
        cache: [ActionID: any Action] = [:],
        rankedFor query: String? = nil
    ) {
        let isRefresh = query != nil && query == listQuery
        let selectedIndex = selectedActionID.flatMap { id in actions.firstIndex { $0.id == id } }
        actions = newActions
        actionCache = cache
        listQuery = query
        guard isRefresh, let selectedIndex, !newActions.isEmpty else {
            selectedActionID = newActions.first?.id
            listResetToken &+= 1
            return
        }
        if let newIndex = newActions.firstIndex(where: { $0.id == selectedActionID }) {
            if newIndex != selectedIndex { selectionRevealToken &+= 1 }
        } else {
            selectedActionID = newActions[min(selectedIndex, newActions.count - 1)].id
        }
    }

    // MARK: - Parameter flow

    func enterParameterMode(action: any Action) {
        activeAction = action
        collectedValues = [:]
        collectedLabels = [:]
        // Pre-fill defaults
        for param in action.parameters {
            if let defaultValue = param.defaultValue {
                collectedValues[param.id] = defaultValue
            }
        }
        advanceToNextParameter(startingFrom: 0)
    }

    func advanceToNextParameter(startingFrom index: Int) {
        guard let action = activeAction else { return }
        let params = action.parameters
        for paramIndex in index ..< params.count {
            let param = params[paramIndex]
            if param.isRequired, collectedValues[param.id] == nil {
                currentParameter = param
                parameterQuery = ""
                parameterOptions = []
                selectedParameterOptionID = nil
                isLoadingOptions = false
                pushMode(.parameterInput(actionID: action.id, parameterIndex: paramIndex))

                // Pre-populate static selection options
                if case let .selection(options) = param.type {
                    parameterOptions = options
                    selectedParameterOptionID = options.first?.id
                } else if case .toggle = param.type {
                    parameterOptions = [
                        ParameterOption(id: "true", label: "On", iconName: "checkmark.circle"),
                        ParameterOption(id: "false", label: "Off", iconName: "xmark.circle"),
                    ]
                    selectedParameterOptionID = "true"
                }
                // For dynamicSelection, the coordinator will fetch options
                return
            }
        }
        // All required parameters filled — signal ready for execution
        // The coordinator checks this and executes
    }

    func confirmParameterValue(_ value: String, forParameterID parameterID: String) {
        collectedValues[parameterID] = value
        // Capture the label now: dynamic options are replaced once the next parameter loads.
        collectedLabels[parameterID] = parameterOptions.first { $0.id == value }?.label ?? value
    }

    /// Labels of the confirmed values in parameter order, for the search-field pill
    /// (Search Wallpapers › Wallhaven).
    var confirmedValueLabels: [String] {
        guard let action = activeAction else { return [] }
        return action.parameters.compactMap { collectedLabels[$0.id] }.filter { !$0.isEmpty }
    }

    var allRequiredParametersFilled: Bool {
        guard let action = activeAction else { return false }
        return action.parameters
            .filter(\.isRequired)
            .allSatisfy { collectedValues[$0.id] != nil }
    }

    var nextUnfilledParameterIndex: Int? {
        guard let action = activeAction else { return nil }
        return action.parameters.firstIndex { $0.isRequired && collectedValues[$0.id] == nil }
    }

    // MARK: - Page navigation

    private let pageSize = 10

    func selectNextPage() {
        switch mode {
        case .search, .pushedActions:
            selectActionByOffset(pageSize)
        case .parameterInput:
            selectParameterOptionByOffset(pageSize)
        }
    }

    func selectPreviousPage() {
        switch mode {
        case .search, .pushedActions:
            selectActionByOffset(-pageSize)
        case .parameterInput:
            selectParameterOptionByOffset(-pageSize)
        }
    }

    private func selectActionByOffset(_ offset: Int) {
        guard !actions.isEmpty else { return }
        guard let currentID = selectedActionID,
              let idx = actions.firstIndex(where: { $0.id == currentID })
        else {
            selectedActionID = offset > 0 ? actions.first?.id : actions.last?.id
            return
        }
        let targetIndex = max(0, min(actions.count - 1, idx + offset))
        selectedActionID = actions[targetIndex].id
    }

    private func selectParameterOptionByOffset(_ offset: Int) {
        guard !parameterOptions.isEmpty else { return }
        guard let currentID = selectedParameterOptionID,
              let idx = parameterOptions.firstIndex(where: { $0.id == currentID })
        else {
            selectedParameterOptionID = offset > 0 ? parameterOptions.first?.id : parameterOptions.last?.id
            return
        }
        let targetIndex = max(0, min(parameterOptions.count - 1, idx + offset))
        selectedParameterOptionID = parameterOptions[targetIndex].id
    }

    // MARK: - Private selection helpers

    private func selectNextAction() {
        guard !actions.isEmpty else { return }
        guard let currentID = selectedActionID,
              let idx = actions.firstIndex(where: { $0.id == currentID })
        else {
            selectedActionID = actions.first?.id
            return
        }
        let next = actions.index(after: idx)
        selectedActionID = (next < actions.endIndex) ? actions[next].id : currentID
    }

    private func selectPreviousAction() {
        guard !actions.isEmpty else { return }
        guard let currentID = selectedActionID,
              let idx = actions.firstIndex(where: { $0.id == currentID })
        else {
            selectedActionID = actions.last?.id
            return
        }
        if idx > actions.startIndex {
            selectedActionID = actions[actions.index(before: idx)].id
        }
    }

    private func selectNextParameterOption() {
        guard !parameterOptions.isEmpty else { return }
        guard let currentID = selectedParameterOptionID,
              let idx = parameterOptions.firstIndex(where: { $0.id == currentID })
        else {
            selectedParameterOptionID = parameterOptions.first?.id
            return
        }
        let next = parameterOptions.index(after: idx)
        selectedParameterOptionID = (next < parameterOptions.endIndex)
            ? parameterOptions[next].id : currentID
    }

    private func selectPreviousParameterOption() {
        guard !parameterOptions.isEmpty else { return }
        guard let currentID = selectedParameterOptionID,
              let idx = parameterOptions.firstIndex(where: { $0.id == currentID })
        else {
            selectedParameterOptionID = parameterOptions.last?.id
            return
        }
        if idx > parameterOptions.startIndex {
            selectedParameterOptionID = parameterOptions[parameterOptions.index(before: idx)].id
        }
    }
}

// MARK: - Mode navigation

/// Outside the class body for its length limit; `modeStack` is private to this file.
extension PickerState {
    /// Pushes `newMode`. With `restoringList`, popping it also puts back the rows, selection
    /// and query on screen now — for a list pushed over a session the user is working in,
    /// which would otherwise be left showing the pushed rows.
    func pushMode(_ newMode: PickerMode, restoringList: Bool = false) {
        let covered = restoringList
            ? CoveredList(
                actions: actions, cache: actionCache, selectedActionID: selectedActionID,
                listQuery: listQuery, query: query
            )
            : nil
        modeStack.append(ModeStackEntry(mode: mode, coveredList: covered))
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = newMode
        }
        Log.picker.debug("Mode pushed: \(String(describing: newMode), privacy: .public)")
    }

    /// Puts `newMode` up with nothing beneath it, so Escape closes the picker rather than
    /// going back — for a list brought up on a picker that was closed and reset.
    func showAsRoot(_ newMode: PickerMode) {
        modeStack = []
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = newMode
        }
    }

    /// Returns `true` if a mode was popped, `false` if already at root.
    func popMode() -> Bool {
        guard let previous = modeStack.popLast() else { return false }
        withAnimation(.easeInOut(duration: 0.2)) {
            mode = previous.mode
        }
        if let list = previous.coveredList {
            actions = list.actions
            actionCache = list.cache
            selectedActionID = list.selectedActionID
            listQuery = list.listQuery
            if query != list.query {
                query = list.query
            }
        }

        // Restore query state when returning to search
        if case .search = mode {
            parameterQuery = ""
            parameterOptions = []
            selectedParameterOptionID = nil
            currentParameter = nil
            isLoadingOptions = false
        }
        return true
    }
}

/// A mode to go back to, with the list a `pushMode(_:restoringList:)` covered.
private struct ModeStackEntry {
    let mode: PickerMode
    let coveredList: CoveredList?
}

private struct CoveredList {
    let actions: [ActionItem]
    let cache: [ActionID: any Action]
    let selectedActionID: ActionID?
    let listQuery: String?
    let query: String
}

// MARK: - ActionItem

struct ActionItem: Identifiable, Equatable, Sendable {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconSystemName: String?
    /// Path to an app bundle whose Finder icon represents this item (apps/windows).
    let appIconPath: String?
    let score: Double
    let moduleID: String
    let hasParameters: Bool
    let keywords: [String]
    var titleHighlightRanges: [Range<String.Index>]?

    init(
        id: ActionID,
        title: String,
        subtitle: String,
        iconSystemName: String? = nil,
        appIconPath: String? = nil,
        score: Double = 0,
        moduleID: String = "",
        hasParameters: Bool = false,
        keywords: [String] = [],
        titleHighlightRanges: [Range<String.Index>]? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconSystemName = iconSystemName
        self.appIconPath = appIconPath
        self.score = score
        self.moduleID = moduleID
        self.hasParameters = hasParameters
        self.keywords = keywords
        self.titleHighlightRanges = titleHighlightRanges
    }
}
