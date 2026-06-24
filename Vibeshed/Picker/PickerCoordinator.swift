import Combine
import CoreFoundation
import Foundation
import UserNotifications

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
    private var actionRefreshTask: Task<Void, Never>?

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
           case .dynamicSelection = param.type
        {
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
        }
    }

    func handleTab() {
        guard case let .parameterInput(_, parameterIndex) = pickerState.mode else { return }
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
        case .parameterInput:
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

    private func executeAction(_ action: any Action, values: ParameterValues) async {
        Log.picker.debug("Executing action '\(action.id, privacy: .public)'")
        panelController.hideAndReset()
        do {
            let result = try await action.run(with: values)
            usageTracker?.recordUsage(actionID: action.id)
            await eventBus.publish(.actionExecuted(action.id, moduleID: action.id.moduleID))
            handleActionResult(result)
        } catch {
            Log.picker
                .error(
                    "Action '\(action.id, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
                )
            await eventBus.publish(.actionFailed(action.id, message: error.localizedDescription))
            postErrorNotification(
                title: action.title,
                body: error.localizedDescription
            )
        }
    }

    private func handleActionResult(_ result: ActionResult) {
        switch result {
        case .dismiss, .showResult:
            break

        case .keepOpen:
            panelController.showRetainingState()

        case let .setQuery(newQuery):
            pickerState.mode = .search
            pickerState.activeAction = nil
            pickerState.collectedValues = [:]
            pickerState.currentParameter = nil
            pickerState.query = newQuery
            panelController.showRetainingState()

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
            panelController.showRetainingState()

        case let .chain(actionID, chainValues):
            Task {
                guard let action = await moduleRegistry.findAction(id: actionID) else {
                    Log.picker.error("Chained action '\(actionID, privacy: .public)' not found")
                    return
                }
                await executeAction(action, values: chainValues)
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
                    // Capture context lazily — only on the first query of a session.
                    await runQuery(
                        query,
                        captureContext: currentContext == nil,
                        preservingSelection: true,
                        layoutCorrectionFallback: true,
                        clearsLoading: true,
                        updatesEmptyCacheWhenEmpty: false
                    )
                }
            }
    }

    /// Applies aliases (cheap, main-actor) then scores/ranks off the main actor.
    /// Scoring is the per-keystroke hot path, so it runs on a detached task to keep
    /// the main thread free during typing.
    private func buildActionItems(
        from actions: [any Action],
        query: String,
        scoring: ScoringContext
    ) async -> ([ActionItem], [ActionID: any Action]) {
        let buildState = Log.signposter.beginInterval("BuildActionItems")
        defer { Log.signposter.endInterval("BuildActionItems", buildState) }

        // Apply aliases: enrich keywords for parameterless aliases,
        // create synthetic actions for parameterized ones. Cheap; stays on main actor.
        let aliasResult = aliasManager?.applyAliases(to: actions)
        let enrichments = aliasResult?.keywordEnrichments ?? [:]
        let allActions: [any Action] = actions + (aliasResult?.syntheticActions ?? [])

        return await Task.detached {
            ActionScorer.scoreAndRank(
                allActions: allActions,
                enrichments: enrichments,
                query: query,
                scoring: scoring
            )
        }.value
    }

    // MARK: - Unified query pipeline

    private func makeScoring(query: String, context: SystemContext?) -> ScoringContext {
        usageTracker?.makeScoringContext(query: query, systemContext: context)
            ?? ScoringContext(usageCounts: [:], lastUsedDates: [:], query: query, systemContext: context)
    }

    /// Single query → score → display pipeline shared by all four entry points
    /// (debounced typing, initial load, refresh-in-place, dynamic refresh). The flags
    /// capture the only differences between them.
    ///
    /// - Parameters:
    ///   - captureContext: capture a fresh `SystemContext` and refresh the theme first.
    ///   - preservingSelection: keep the current selection across the list update.
    ///   - layoutCorrectionFallback: on empty results, retry via keyboard transliteration.
    ///   - clearsLoading: set `isLoading = false` when finished.
    ///   - updatesEmptyCacheWhenEmpty: refresh the empty-query cache when `query` is empty.
    private func runQuery(
        _ query: String,
        captureContext: Bool,
        preservingSelection: Bool,
        layoutCorrectionFallback: Bool,
        clearsLoading: Bool,
        updatesEmptyCacheWhenEmpty: Bool
    ) async {
        let pipelineState = Log.signposter.beginInterval("QueryPipeline")
        defer { Log.signposter.endInterval("QueryPipeline", pipelineState) }

        if captureContext {
            currentContext = SystemContext.capture()
            if let ctx = currentContext {
                await themeEngine?.refresh(context: ctx)
            }
        }
        let ctx = currentContext

        func finish(_ items: [ActionItem], _ cache: [ActionID: any Action]) {
            pickerState.updateActions(items, cache: cache, preservingSelection: preservingSelection)
            if clearsLoading { pickerState.isLoading = false }
            if updatesEmptyCacheWhenEmpty, query.isEmpty {
                cachedEmptyQueryItems = items
                cachedEmptyQueryActionCache = cache
            }
        }

        let scoring = makeScoring(query: query, context: ctx)
        let results = await moduleRegistry.queryAll(query: query, scoring: scoring)
        guard case .search = pickerState.mode else { return }
        let (items, cache) = await buildActionItems(from: results, query: query, scoring: scoring)
        guard case .search = pickerState.mode else { return }

        // Layout correction fallback: if no results and query is non-empty,
        // try transliterating from the current keyboard layout.
        if layoutCorrectionFallback, !query.isEmpty, items.isEmpty,
           let correction = layoutTransliterator?.transliterate(query)
        {
            let correctedScoring = makeScoring(query: correction.correctedQuery, context: ctx)
            let correctedResults = await moduleRegistry.queryAll(
                query: correction.correctedQuery, scoring: correctedScoring
            )
            guard case .search = pickerState.mode else { return }
            let (correctedItems, correctedCache) = await buildActionItems(
                from: correctedResults, query: correction.correctedQuery, scoring: correctedScoring
            )
            guard case .search = pickerState.mode else { return }
            if !correctedItems.isEmpty {
                pickerState.layoutCorrectionHint = correction
                finish(correctedItems, correctedCache)
                return
            }
        }

        if layoutCorrectionFallback {
            pickerState.layoutCorrectionHint = nil
        }
        finish(items, cache)
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
               pickerState.currentParameter?.id == param.id
            {
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
        actionRefreshTask = Task { [weak self] in
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
           let cachedCache = cachedEmptyQueryActionCache
        {
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
            await runQuery(
                "",
                captureContext: true,
                preservingSelection: true,
                layoutCorrectionFallback: false,
                clearsLoading: true,
                updatesEmptyCacheWhenEmpty: true
            )
        }
    }

    /// Re-shows the picker with retained state. Refreshes context and re-scores
    /// existing actions in the background without clearing the list.
    func refreshInPlace() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await runQuery(
                pickerState.query,
                captureContext: true,
                preservingSelection: true,
                layoutCorrectionFallback: false,
                clearsLoading: false,
                updatesEmptyCacheWhenEmpty: true
            )
        }
    }

    /// Invalidates the empty-query cache so the next fresh open re-queries modules.
    private func invalidateEmptyQueryCache() {
        cachedEmptyQueryItems = nil
        cachedEmptyQueryActionCache = nil
    }

    func refreshActions() async {
        await runQuery(
            pickerState.query,
            captureContext: false,
            preservingSelection: true,
            layoutCorrectionFallback: true,
            clearsLoading: false,
            updatesEmptyCacheWhenEmpty: false
        )
    }
}

// MARK: - Notifications

private func postErrorNotification(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let request = UNNotificationRequest(
        identifier: "vibeshed.action.error.\(UUID().uuidString)",
        content: content,
        trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
        if let error {
            Log.picker.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
        }
    }
}
