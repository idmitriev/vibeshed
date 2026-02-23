import Combine
import Foundation
import OSLog

@MainActor
@Observable
final class PickerState {
    var query: String = "" {
        didSet { querySubject.send(query) }
    }

    var actions: [ActionItem] = []
    var selectedActionID: ActionID?
    var isLoading: Bool = false

    // MARK: - Mode state machine

    var mode: PickerMode = .search
    private var modeStack: [PickerMode] = []

    // MARK: - Parameter binding state

    var activeAction: (any Action)?
    var collectedValues: [String: Any] = [:]
    var currentParameter: ActionParameter?
    var parameterOptions: [ParameterOption] = []
    var selectedParameterOptionID: String?
    var isLoadingOptions: Bool = false

    var parameterQuery: String = "" {
        didSet { parameterQuerySubject.send(parameterQuery) }
    }

    // MARK: - Action cache (not tracked by @Observable for perf)

    @ObservationIgnored var actionCache: [ActionID: any Action] = [:]

    // MARK: - Publishers

    private let querySubject = PassthroughSubject<String, Never>()
    private let parameterQuerySubject = PassthroughSubject<String, Never>()

    var debouncedQuery: AnyPublisher<String, Never> {
        querySubject
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var debouncedParameterQuery: AnyPublisher<String, Never> {
        parameterQuerySubject
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    // MARK: - Mode navigation

    func pushMode(_ newMode: PickerMode) {
        modeStack.append(mode)
        mode = newMode
        Log.picker.debug("Mode pushed: \(String(describing: newMode), privacy: .public)")
    }

    /// Returns `true` if a mode was popped, `false` if already at root (search).
    func popMode() -> Bool {
        guard let previous = modeStack.popLast() else { return false }
        mode = previous

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

    // MARK: - Reset

    func reset() {
        query = ""
        parameterQuery = ""
        actions = []
        selectedActionID = nil
        isLoading = false
        mode = .search
        modeStack = []
        activeAction = nil
        collectedValues = [:]
        currentParameter = nil
        parameterOptions = []
        selectedParameterOptionID = nil
        isLoadingOptions = false
        actionCache = [:]
    }

    // MARK: - Selection navigation

    func selectNext() {
        switch mode {
        case .search, .pushedActions:
            selectNextAction()
        case .parameterInput:
            selectNextParameterOption()
        case .result:
            break
        }
    }

    func selectPrevious() {
        switch mode {
        case .search, .pushedActions:
            selectPreviousAction()
        case .parameterInput:
            selectPreviousParameterOption()
        case .result:
            break
        }
    }

    // MARK: - Action list updates (with selection stability)

    func updateActions(_ newActions: [ActionItem], cache: [ActionID: any Action] = [:], preservingSelection: Bool = true) {
        let previousSelection = selectedActionID
        actions = newActions
        actionCache = cache
        if preservingSelection, let prev = previousSelection,
           newActions.contains(where: { $0.id == prev }) {
            selectedActionID = prev
        } else {
            selectedActionID = newActions.first?.id
        }
    }

    // MARK: - Parameter flow

    func enterParameterMode(action: any Action) {
        activeAction = action
        collectedValues = [:]
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
        for i in index ..< params.count {
            let param = params[i]
            if param.isRequired, collectedValues[param.id] == nil {
                currentParameter = param
                parameterQuery = ""
                parameterOptions = []
                selectedParameterOptionID = nil
                isLoadingOptions = false
                pushMode(.parameterInput(actionID: action.id, parameterIndex: i))

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

    func confirmParameterValue(_ value: Any, forParameterID parameterID: String) {
        collectedValues[parameterID] = value
    }

    var allRequiredParametersFilled: Bool {
        guard let action = activeAction else { return false }
        return action.parameters
            .filter(\.isRequired)
            .allSatisfy { collectedValues[$0.id] != nil }
    }

    var nextUnfilledParameterIndex: Int? {
        guard let action = activeAction else { return nil }
        let params = action.parameters
        for (i, param) in params.enumerated() {
            if param.isRequired, collectedValues[param.id] == nil {
                return i
            }
        }
        return nil
    }

    // MARK: - Page navigation

    private let pageSize = 10

    func selectNextPage() {
        switch mode {
        case .search, .pushedActions:
            selectActionByOffset(pageSize)
        case .parameterInput:
            selectParameterOptionByOffset(pageSize)
        case .result:
            break
        }
    }

    func selectPreviousPage() {
        switch mode {
        case .search, .pushedActions:
            selectActionByOffset(-pageSize)
        case .parameterInput:
            selectParameterOptionByOffset(-pageSize)
        case .result:
            break
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

// MARK: - ActionItem

struct ActionItem: Identifiable, Equatable, Sendable {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconSystemName: String?
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
        self.score = score
        self.moduleID = moduleID
        self.hasParameters = hasParameters
        self.keywords = keywords
        self.titleHighlightRanges = titleHighlightRanges
    }
}
