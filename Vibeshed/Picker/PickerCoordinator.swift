import Combine
import CoreFoundation
import Foundation

@MainActor
@Observable
final class PickerCoordinator {
    private let pickerState: PickerState
    private let moduleRegistry: ModuleRegistry
    private let panelController: PanelController
    private let eventBus: EventBus
    var usageTracker: UsageTracker?
    var themeEngine: ThemeEngine?
    var aliasManager: AliasManager?
    var layoutTransliterator: LayoutTransliterator?

    private var currentContext: SystemContext?
    private var parameterQuerySubscription: AnyCancellable?
    private var querySubscription: AnyCancellable?
    private var actionRefreshSubscription: Any?

    // MARK: - Empty-query cache (instant display on re-open)

    @ObservationIgnored private var cachedEmptyQueryItems: [ActionItem]?
    @ObservationIgnored private var cachedEmptyQueryActionCache: [ActionID: any Action]?

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

    // MARK: - Public API

    /// Shows the picker in parameter-input mode for the given action.
    /// Called from keybinding executor when an action has required parameters.
    func showForParameterInput(action: any Action) {
        panelController.show()
        pickerState.enterParameterMode(action: action)
        // Trigger initial fetch for dynamicSelection
        if let param = pickerState.currentParameter,
           case .dynamicSelection = param.type {
            fetchParameterOptions(for: param, actionID: action.id, query: "")
        }
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
            panelController.hideAndReset()
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

    func handleCmdNumber(_ number: Int) {
        let index = number - 1
        switch pickerState.mode {
        case .search, .pushedActions:
            activateAction(at: index)
        case .parameterInput:
            guard index < pickerState.parameterOptions.count else { return }
            pickerState.selectedParameterOptionID = pickerState.parameterOptions[index].id
            handleReturnInParameterMode()
        case .result:
            break
        }
    }

    // MARK: - Return handlers per mode

    private func handleReturnInActionList() {
        guard let selectedID = pickerState.selectedActionID,
              let idx = pickerState.actions.firstIndex(where: { $0.id == selectedID })
        else { return }
        activateAction(at: idx)
    }

    /// Activate an action by ID — used by mouse-click handlers in the list view.
    func activateAction(id: ActionID) {
        switch pickerState.mode {
        case .search, .pushedActions:
            break
        case .parameterInput, .result:
            return
        }
        guard let idx = pickerState.actions.firstIndex(where: { $0.id == id }) else { return }
        activateAction(at: idx)
    }

    private func activateAction(at index: Int) {
        guard index >= 0, index < pickerState.actions.count else { return }
        let targetItem = pickerState.actions[index]
        pickerState.selectedActionID = targetItem.id
        pickerState.bumpActivation(for: targetItem.id)
        guard let action = pickerState.actionCache[targetItem.id] else { return }

        let requiredParams = action.parameters.filter(\.isRequired)
        if requiredParams.isEmpty {
            Task { await executeAction(action, values: [:]) }
        } else {
            pickerState.enterParameterMode(action: action)
            // Trigger initial fetch for dynamicSelection
            if let param = pickerState.currentParameter,
               case .dynamicSelection = param.type {
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
               let action = pickerState.activeAction {
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
        Log.picker.debug("Executing action '\(action.id, privacy: .public)'")
        do {
            let result = try await action.run(with: values)
            usageTracker?.recordUsage(actionID: action.id)
            await eventBus.publish(.actionExecuted(action.id, moduleID: action.id.moduleID))
            handleActionResult(result)
        } catch {
            Log.picker.error("Action '\(action.id, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
            await eventBus.publish(.actionFailed(action.id, message: error.localizedDescription))
            pickerState.pushMode(.result(title: "Error", body: error.localizedDescription))
        }
    }

    private func handleActionResult(_ result: ActionResult) {
        switch result {
        case .dismiss:
            panelController.hideAndReset()

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
                    moduleID: action.id.moduleID,
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
                    Log.picker.error("Chained action '\(actionID, privacy: .public)' not found")
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
                    let pipelineState = Log.signposter.beginInterval("QueryPipeline")
                    defer { Log.signposter.endInterval("QueryPipeline", pipelineState) }
                    if currentContext == nil {
                        currentContext = SystemContext.capture()
                        if let ctx = currentContext {
                            await self.themeEngine?.refresh(context: ctx)
                        }
                    }
                    let ctx = currentContext
                    let scoring = usageTracker?.makeScoringContext(query: query, systemContext: ctx)
                        ?? ScoringContext(usageCounts: [:], lastUsedDates: [:], query: query, systemContext: ctx)
                    let results = await moduleRegistry.queryAll(query: query, scoring: scoring)
                    guard case .search = pickerState.mode else { return }

                    let (items, cache) = buildActionItems(from: results, query: query, scoring: scoring)

                    // Layout correction fallback: if no results and query is non-empty,
                    // try transliterating from the current keyboard layout.
                    if !query.isEmpty, items.isEmpty,
                       let correction = layoutTransliterator?.transliterate(query) {
                        let correctedScoring = usageTracker?.makeScoringContext(
                            query: correction.correctedQuery, systemContext: ctx
                        ) ?? ScoringContext(
                            usageCounts: [:], lastUsedDates: [:],
                            query: correction.correctedQuery, systemContext: ctx
                        )
                        let correctedResults = await moduleRegistry.queryAll(
                            query: correction.correctedQuery, scoring: correctedScoring
                        )
                        guard case .search = pickerState.mode else { return }
                        let (correctedItems, correctedCache) = buildActionItems(
                            from: correctedResults,
                            query: correction.correctedQuery,
                            scoring: correctedScoring
                        )
                        if !correctedItems.isEmpty {
                            pickerState.layoutCorrectionHint = correction
                            pickerState.updateActions(correctedItems, cache: correctedCache)
                            pickerState.isLoading = false
                            return
                        }
                    }

                    pickerState.layoutCorrectionHint = nil
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
        let buildState = Log.signposter.beginInterval("BuildActionItems")
        defer { Log.signposter.endInterval("BuildActionItems", buildState) }

        // Apply aliases: enrich keywords for parameterless aliases,
        // create synthetic actions for parameterized ones
        let aliasResult = aliasManager?.applyAliases(to: actions)
        let enrichments = aliasResult?.keywordEnrichments ?? [:]
        let allActions: [any Action] = actions + (aliasResult?.syntheticActions ?? [])

        var scored: [(item: ActionItem, action: any Action, score: Double)] = []
        var cache: [ActionID: any Action] = [:]

        for action in allActions {
            let extraKeywords = enrichments[action.id] ?? []
            let combinedKeywords = action.keywords + extraKeywords

            let usageBoost = scoring.usageBoost(for: action.id)
            let result = FuzzyMatcher.score(
                query: query,
                title: action.title,
                subtitle: action.subtitle,
                keywords: combinedKeywords,
                relevanceScore: action.relevanceScore,
                usageBoost: usageBoost
            )

            // If query is non-empty and fuzzy matcher rejects, skip
            guard let result else { continue }

            let moduleID = action.id.moduleID
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
                keywords: combinedKeywords,
                titleHighlightRanges: result.titleRanges.isEmpty ? nil : result.titleRanges
            )
            scored.append((item: item, action: action, score: finalScore))
            cache[action.id] = action
        }

        scored.sort { $0.score > $1.score }

        // Cap results to avoid rendering huge lists — nobody scrolls past 200 in a launcher.
        let maxResults = 200
        if scored.count > maxResults {
            let dropped = scored[maxResults...]
            for entry in dropped {
                cache.removeValue(forKey: entry.action.id)
            }
            scored = Array(scored.prefix(maxResults))
        }

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
                    if query.isEmpty {
                        pickerState.parameterOptions = options
                    } else {
                        pickerState.parameterOptions = fuzzyFilterOptions(options, query: query)
                    }
                    pickerState.selectedParameterOptionID = pickerState.parameterOptions.first?.id
                default:
                    break
                }
            }
    }

    private func fetchParameterOptions(for param: ActionParameter, actionID: ActionID, query: String) {
        let moduleID = actionID.moduleID
        guard let module = moduleRegistry.module(id: moduleID) else { return }
        pickerState.isLoadingOptions = true
        Task { @MainActor in
            let options = await module.provideParameterOptions(
                for: param.id, in: actionID, query: query
            )
            // Only apply if still in the same parameter mode
            if case let .parameterInput(currentActionID, _) = pickerState.mode,
               currentActionID == actionID,
               pickerState.currentParameter?.id == param.id {
                let filtered = query.isEmpty ? options : fuzzyFilterOptions(options, query: query)
                pickerState.parameterOptions = filtered
                pickerState.selectedParameterOptionID = filtered.first?.id
                pickerState.isLoadingOptions = false
            }
        }
    }

    private func fuzzyFilterOptions(_ options: [ParameterOption], query: String) -> [ParameterOption] {
        var scored: [(option: ParameterOption, score: Double)] = []
        for option in options {
            guard let result = FuzzyMatcher.match(query: query, against: option.label) else { continue }
            var opt = option
            opt.labelHighlightRanges = result.matchedRanges.isEmpty ? nil : result.matchedRanges
            scored.append((option: opt, score: result.score))
        }
        scored.sort { $0.score > $1.score }
        return scored.map(\.option)
    }

    // MARK: - Dynamic action refresh

    private func wireActionRefresh() {
        Task { [weak self] in
            guard let self else { return }
            let (_, stream) = await eventBus.subscribe()
            for await event in stream {
                switch event {
                case .moduleActionsChanged:
                    invalidateEmptyQueryCache()
                    if panelController.isVisible, case .search = pickerState.mode {
                        await refreshActions()
                    }
                case .configReloaded, .moduleRegistered, .moduleUnregistered:
                    invalidateEmptyQueryCache()
                default:
                    break
                }
            }
        }
    }

    func clearContext() {
        currentContext = nil
    }

    /// Shows cached empty-query results synchronously without triggering any async work.
    /// Called before the show animation so the user sees content immediately.
    func showCachedActionsIfAvailable() {
        if let cachedItems = cachedEmptyQueryItems,
           let cachedCache = cachedEmptyQueryActionCache {
            pickerState.updateActions(cachedItems, cache: cachedCache)
            pickerState.isLoading = false
        } else {
            pickerState.isLoading = true
        }
    }

    /// Triggers an immediate (non-debounced) query to populate the action list.
    /// Called after the show animation completes so re-renders don't contend with animation.
    func loadInitialActions() {
        // If no cache was shown before animation, show loading state
        if cachedEmptyQueryItems == nil {
            pickerState.isLoading = true
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            currentContext = SystemContext.capture()
            if let ctx = currentContext {
                await self.themeEngine?.refresh(context: ctx)
            }
            let ctx = currentContext
            let scoring = usageTracker?.makeScoringContext(query: "", systemContext: ctx)
                ?? ScoringContext(usageCounts: [:], lastUsedDates: [:], query: "", systemContext: ctx)
            let results = await moduleRegistry.queryAll(query: "", scoring: scoring)
            guard case .search = pickerState.mode else { return }
            let (items, cache) = buildActionItems(from: results, query: "", scoring: scoring)
            pickerState.updateActions(items, cache: cache)
            pickerState.isLoading = false

            // Update cache for next open
            cachedEmptyQueryItems = items
            cachedEmptyQueryActionCache = cache
        }
    }

    /// Re-shows the picker with retained state. Refreshes context and re-scores
    /// existing actions in the background without clearing the list.
    func refreshInPlace() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            currentContext = SystemContext.capture()
            if let ctx = currentContext {
                await self.themeEngine?.refresh(context: ctx)
            }
            let query = pickerState.query
            let ctx = currentContext
            let scoring = usageTracker?.makeScoringContext(query: query, systemContext: ctx)
                ?? ScoringContext(usageCounts: [:], lastUsedDates: [:], query: query, systemContext: ctx)
            let results = await moduleRegistry.queryAll(query: query, scoring: scoring)
            guard case .search = pickerState.mode else { return }
            let (items, cache) = buildActionItems(from: results, query: query, scoring: scoring)
            pickerState.updateActions(items, cache: cache, preservingSelection: true)

            // Update empty-query cache if applicable
            if query.isEmpty {
                cachedEmptyQueryItems = items
                cachedEmptyQueryActionCache = cache
            }
        }
    }

    /// Invalidates the empty-query cache so the next fresh open re-queries modules.
    private func invalidateEmptyQueryCache() {
        cachedEmptyQueryItems = nil
        cachedEmptyQueryActionCache = nil
    }

    func refreshActions() async {
        let query = pickerState.query
        let ctx = currentContext
        let scoring = usageTracker?.makeScoringContext(query: query, systemContext: ctx)
            ?? ScoringContext(usageCounts: [:], lastUsedDates: [:], query: query, systemContext: ctx)
        let results = await moduleRegistry.queryAll(query: query, scoring: scoring)
        guard case .search = pickerState.mode else { return }

        let (items, cache) = buildActionItems(from: results, query: query, scoring: scoring)

        if !query.isEmpty, items.isEmpty,
           let correction = layoutTransliterator?.transliterate(query) {
            let correctedScoring = usageTracker?.makeScoringContext(
                query: correction.correctedQuery, systemContext: ctx
            ) ?? ScoringContext(
                usageCounts: [:], lastUsedDates: [:],
                query: correction.correctedQuery, systemContext: ctx
            )
            let correctedResults = await moduleRegistry.queryAll(
                query: correction.correctedQuery, scoring: correctedScoring
            )
            guard case .search = pickerState.mode else { return }
            let (correctedItems, correctedCache) = buildActionItems(
                from: correctedResults,
                query: correction.correctedQuery,
                scoring: correctedScoring
            )
            if !correctedItems.isEmpty {
                pickerState.layoutCorrectionHint = correction
                pickerState.updateActions(correctedItems, cache: correctedCache, preservingSelection: true)
                return
            }
        }

        pickerState.layoutCorrectionHint = nil
        pickerState.updateActions(items, cache: cache, preservingSelection: true)
    }
}
