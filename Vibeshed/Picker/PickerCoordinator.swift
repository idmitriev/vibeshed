import Combine
import Foundation

@MainActor
@Observable
final class PickerCoordinator {
    private let pickerState: PickerState
    private let moduleRegistry: ModuleRegistry
    private let panelController: PanelController
    private let eventBus: EventBus
    var usageTracker: UsageTracker?

    private var currentContext: SystemContext?
    private var parameterQuerySubscription: AnyCancellable?
    private var querySubscription: AnyCancellable?
    private var actionRefreshSubscription: Any?

    init(
        pickerState: PickerState,
        moduleRegistry: ModuleRegistry,
        panelController: PanelController,
        eventBus: EventBus
    ) {
        self.pickerState = pickerState
        self.moduleRegistry = moduleRegistry
        self.panelController = panelController
        self.eventBus = eventBus
    }

    // MARK: - Setup

    func start() {
        wireQueryToModules()
        wireParameterQuery()
        wireActionRefresh()
    }

    // MARK: - Keyboard handlers

    func handleReturn() {
        switch pickerState.mode {
        case .search, .pushedActions:
            handleReturnInActionList()
        case .parameterInput:
            handleReturnInParameterMode()
        case .result:
            panelController.hide()
        }
    }

    func handleTab() {
        guard case .parameterInput(_, let parameterIndex) = pickerState.mode else { return }
        // Skip current optional parameter and advance
        pickerState.advanceToNextParameter(startingFrom: parameterIndex + 1)
        if pickerState.allRequiredParametersFilled {
            executeActiveAction()
        }
    }

    // MARK: - Return handlers per mode

    private func handleReturnInActionList() {
        guard let selectedID = pickerState.selectedActionID,
              let action = pickerState.actionCache[selectedID]
        else { return }

        let requiredParams = action.parameters.filter(\.isRequired)
        if requiredParams.isEmpty {
            Task { await executeAction(action, values: [:]) }
        } else {
            pickerState.enterParameterMode(action: action)
            // Trigger initial fetch for dynamicSelection
            if let param = pickerState.currentParameter,
               case .dynamicSelection = param.type
            {
                fetchParameterOptions(for: param, actionID: action.id, query: "")
            }
        }
    }

    private func handleReturnInParameterMode() {
        guard let param = pickerState.currentParameter else { return }

        switch param.type {
        case .selection, .dynamicSelection:
            guard let selectedID = pickerState.selectedParameterOptionID else { return }
            pickerState.confirmParameterValue(selectedID, forParameterID: param.id)

        case .text, .path:
            let value = pickerState.parameterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty || !param.isRequired else { return }
            pickerState.confirmParameterValue(value, forParameterID: param.id)

        case .number:
            let value = pickerState.parameterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            guard let number = Double(value) else { return }
            if case let .number(min, max) = param.type {
                if let min, number < min { return }
                if let max, number > max { return }
            }
            pickerState.confirmParameterValue(value, forParameterID: param.id)

        case .toggle:
            guard let selectedID = pickerState.selectedParameterOptionID else { return }
            pickerState.confirmParameterValue(selectedID, forParameterID: param.id)
        }

        // Check if all required params are filled
        if pickerState.allRequiredParametersFilled {
            executeActiveAction()
        } else if let nextIndex = pickerState.nextUnfilledParameterIndex {
            // Pop current parameter mode and advance to next
            _ = pickerState.popMode()
            pickerState.advanceToNextParameter(startingFrom: nextIndex)
            // Trigger fetch for dynamicSelection
            if let nextParam = pickerState.currentParameter,
               case .dynamicSelection = nextParam.type,
               let action = pickerState.activeAction
            {
                fetchParameterOptions(for: nextParam, actionID: action.id, query: "")
            }
        }
    }

    // MARK: - Action execution

    private func executeActiveAction() {
        guard let action = pickerState.activeAction else { return }
        let values = pickerState.collectedValues
        Task { await executeAction(action, values: values) }
    }

    private func executeAction(_ action: any Action, values: [String: Any]) async {
        do {
            let result = try await action.run(with: values)
            usageTracker?.recordUsage(actionID: action.id)
            await eventBus.publish(.actionExecuted(action.id, moduleID: String(action.id.rawValue.prefix(while: { $0 != "." }))))
            handleActionResult(result)
        } catch {
            Log.picker.error("Action '\(action.id)' failed: \(error.localizedDescription)")
            await eventBus.publish(.actionFailed(action.id, message: error.localizedDescription))
            pickerState.pushMode(.result(title: "Error", body: error.localizedDescription))
        }
    }

    private func handleActionResult(_ result: ActionResult) {
        switch result {
        case .dismiss:
            panelController.hide()

        case .keepOpen:
            break

        case let .setQuery(newQuery):
            // Reset to search mode and set the query
            pickerState.mode = .search
            pickerState.activeAction = nil
            pickerState.collectedValues = [:]
            pickerState.currentParameter = nil
            pickerState.query = newQuery

        case let .pushActions(actions):
            let items = actions.map { action in
                ActionItem(
                    id: action.id,
                    title: action.title,
                    subtitle: action.subtitle,
                    iconSystemName: action.iconName,
                    score: action.relevanceScore,
                    moduleID: String(action.id.rawValue.prefix(while: { $0 != "." })),
                    hasParameters: !action.parameters.filter(\.isRequired).isEmpty,
                    keywords: action.keywords
                )
            }
            var cache: [ActionID: any Action] = [:]
            for action in actions {
                cache[action.id] = action
            }
            pickerState.pushMode(.pushedActions)
            pickerState.updateActions(items, cache: cache)

        case let .showResult(title, body):
            pickerState.pushMode(.result(title: title, body: body))

        case let .chain(actionID, stringValues):
            Task {
                guard let action = await moduleRegistry.findAction(id: actionID) else {
                    Log.picker.error("Chained action '\(actionID)' not found")
                    return
                }
                var values: [String: Any] = [:]
                for (key, value) in stringValues {
                    values[key] = value
                }
                await executeAction(action, values: values)
            }
        }
    }

    // MARK: - Query wiring

    private func wireQueryToModules() {
        querySubscription = pickerState.debouncedQuery
            .sink { [weak self] query in
                guard let self else { return }
                guard case .search = pickerState.mode else { return }
                pickerState.isLoading = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if currentContext == nil {
                        currentContext = SystemContext.capture()
                    }
                    let ctx = currentContext
                    let scoring = usageTracker?.makeScoringContext(query: query, systemContext: ctx)
                        ?? ScoringContext(usageCounts: [:], lastUsedDates: [:], query: query, systemContext: ctx)
                    let results = await moduleRegistry.queryAll(query: query, scoring: scoring)
                    guard case .search = pickerState.mode else { return }

                    let (items, cache) = buildActionItems(from: results, query: query, scoring: scoring)
                    pickerState.updateActions(items, cache: cache)
                    pickerState.isLoading = false
                }
            }
    }

    private func buildActionItems(
        from actions: [any Action],
        query: String,
        scoring: ScoringContext
    ) -> ([ActionItem], [ActionID: any Action]) {
        var scored: [(item: ActionItem, action: any Action, score: Double)] = []
        var cache: [ActionID: any Action] = [:]

        for action in actions {
            let usageBoost = scoring.usageBoost(for: action.id)
            let result = FuzzyMatcher.score(
                query: query,
                title: action.title,
                subtitle: action.subtitle,
                keywords: action.keywords,
                relevanceScore: action.relevanceScore,
                usageBoost: usageBoost
            )

            // If query is non-empty and fuzzy matcher rejects, skip
            guard let result else { continue }

            let moduleID = String(action.id.rawValue.prefix(while: { $0 != "." }))
            let contextBoost: Double
            if let ctx = scoring.systemContext {
                contextBoost = ContextualScorer.boost(
                    actionID: action.id, moduleID: moduleID, context: ctx
                )
            } else {
                contextBoost = 0
            }
            let finalScore = result.score + contextBoost

            let item = ActionItem(
                id: action.id,
                title: action.title,
                subtitle: action.subtitle,
                iconSystemName: action.iconName,
                score: finalScore,
                moduleID: moduleID,
                hasParameters: !action.parameters.filter(\.isRequired).isEmpty,
                keywords: action.keywords,
                titleHighlightRanges: result.titleRanges.isEmpty ? nil : result.titleRanges
            )
            scored.append((item: item, action: action, score: finalScore))
            cache[action.id] = action
        }

        scored.sort { $0.score > $1.score }
        return (scored.map(\.item), cache)
    }

    // MARK: - Parameter option fetching

    private func wireParameterQuery() {
        parameterQuerySubscription = pickerState.debouncedParameterQuery
            .sink { [weak self] query in
                guard let self else { return }
                guard case let .parameterInput(actionID, _) = pickerState.mode,
                      let param = pickerState.currentParameter
                else { return }

                switch param.type {
                case .dynamicSelection:
                    fetchParameterOptions(for: param, actionID: actionID, query: query)
                case let .selection(options):
                    // Filter static options client-side
                    if query.isEmpty {
                        pickerState.parameterOptions = options
                    } else {
                        let lowered = query.lowercased()
                        pickerState.parameterOptions = options.filter {
                            $0.label.lowercased().contains(lowered)
                        }
                    }
                    pickerState.selectedParameterOptionID = pickerState.parameterOptions.first?.id
                default:
                    break
                }
            }
    }

    private func fetchParameterOptions(for param: ActionParameter, actionID: ActionID, query: String) {
        let moduleID = String(actionID.rawValue.prefix(while: { $0 != "." }))
        guard let module = moduleRegistry.module(id: moduleID) else { return }
        pickerState.isLoadingOptions = true
        Task { @MainActor in
            let options = await module.provideParameterOptions(
                for: param.id, in: actionID, query: query
            )
            // Only apply if still in the same parameter mode
            if case let .parameterInput(currentActionID, _) = pickerState.mode,
               currentActionID == actionID,
               pickerState.currentParameter?.id == param.id
            {
                pickerState.parameterOptions = options
                pickerState.selectedParameterOptionID = options.first?.id
                pickerState.isLoadingOptions = false
            }
        }
    }

    // MARK: - Dynamic action refresh

    private func wireActionRefresh() {
        Task { [weak self] in
            guard let self else { return }
            let (_, stream) = await eventBus.subscribe()
            for await event in stream {
                if case .moduleActionsChanged = event,
                   panelController.isVisible,
                   case .search = pickerState.mode
                {
                    await refreshActions()
                }
            }
        }
    }

    func clearContext() {
        currentContext = nil
    }

    func refreshActions() async {
        let query = pickerState.query
        let ctx = currentContext
        let scoring = usageTracker?.makeScoringContext(query: query, systemContext: ctx)
            ?? ScoringContext(usageCounts: [:], lastUsedDates: [:], query: query, systemContext: ctx)
        let results = await moduleRegistry.queryAll(query: query, scoring: scoring)
        guard case .search = pickerState.mode else { return }

        let (items, cache) = buildActionItems(from: results, query: query, scoring: scoring)
        pickerState.updateActions(items, cache: cache, preservingSelection: true)
    }
}
