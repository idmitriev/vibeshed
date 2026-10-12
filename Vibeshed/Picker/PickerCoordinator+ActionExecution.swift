import Foundation

/// Running an action and acting on its result. Kept out of PickerCoordinator.swift
/// for file length; `executeAction` is internal (not private) because the
/// coordinator's return handlers call it.
extension PickerCoordinator {
    /// Runs `action`, closing the picker first unless `keepOpen` — a Shift run, which
    /// leaves the picker as the activation set it up for the next run
    /// (`PickerState.prepareForAnotherRun`), chained actions included. The picker then
    /// holds on to keyboard focus if an app the action brings forward takes it.
    ///
    /// An action that types into the user's app (paste on select) can't run with the
    /// picker focused, so it closes the picker even on a Shift run.
    func executeAction(_ action: any Action, values: ParameterValues, keepOpen: Bool = false) async {
        let keepOpen = keepOpen && !action.typesIntoFrontmostApp
        Log.picker.debug("Executing action '\(action.id, privacy: .public)', keepOpen: \(keepOpen)")
        if keepOpen {
            panelController.holdKeyFocusThroughActions()
        } else {
            panelController.hideAndReset()
        }
        do {
            let result = try await action.run(with: values)
            usageTracker?.recordUsage(actionID: action.id)
            await handleActionResult(result, of: action, keepOpen: keepOpen)
        } catch {
            Log.picker
                .error(
                    "Action '\(action.id, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
                )
            await showMessage(PickerMessageAction(
                source: action.id,
                title: action.title,
                body: error.localizedDescription,
                isFailure: true
            ))
        }
    }

    private func handleActionResult(_ result: ActionResult, of action: any Action, keepOpen: Bool) async {
        switch result {
        case .dismiss:
            break

        case let .showResult(title, body):
            await showMessage(PickerMessageAction(source: action.id, title: title, body: body, isFailure: false))

        case .keepOpen:
            // A run that kept the picker open has nothing to bring back — and if the
            // picker was closed since, that was the user's doing.
            if !keepOpen {
                panelController.showRetainingState()
            }

        case let .pushActions(actions):
            showPushedActions(actions)

        case let .chain(actionID, chainValues):
            Task {
                guard let action = await moduleRegistry.findAction(id: actionID) else {
                    Log.picker.error("Chained action '\(actionID, privacy: .public)' not found")
                    return
                }
                await executeAction(action, values: chainValues, keepOpen: keepOpen)
            }
        }
    }

    /// Posts a result or failure as a notification, or — when notifications aren't allowed —
    /// brings the picker back with it as the only row, so it's never silently dropped.
    private func showMessage(_ message: PickerMessageAction) async {
        guard await !postActionNotification(title: message.title, body: message.body) else { return }
        showPushedActions([message])
    }

    private func showPushedActions(_ actions: [any Action]) {
        let items = actions.map(ActionItem.init(pushed:))
        var cache: [ActionID: any Action] = [:]
        for action in actions {
            cache[action.id] = action
        }
        pickerState.pushMode(.pushedActions)
        pickerState.updateActions(items, cache: cache)
        // Re-presenting a picker that's still up would replay its show animation.
        if !panelController.isVisible {
            panelController.showRetainingState()
        }
    }
}
