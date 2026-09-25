import Foundation

/// Running an action and acting on its result. Kept out of PickerCoordinator.swift
/// for file length; `executeAction` is internal (not private) because the
/// coordinator's return handlers call it.
extension PickerCoordinator {
    func executeAction(_ action: any Action, values: ParameterValues) async {
        Log.picker.debug("Executing action '\(action.id, privacy: .public)'")
        panelController.hideAndReset()
        do {
            let result = try await action.run(with: values)
            usageTracker?.recordUsage(actionID: action.id)
            handleActionResult(result)
        } catch {
            Log.picker
                .error(
                    "Action '\(action.id, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
                )
            postActionNotification(
                title: action.title,
                body: error.localizedDescription
            )
        }
    }

    private func handleActionResult(_ result: ActionResult) {
        switch result {
        case .dismiss:
            break

        case let .showResult(title, body):
            postActionNotification(title: title, body: body)

        case .keepOpen:
            panelController.showRetainingState()

        case let .pushActions(actions):
            let items = actions.map(ActionItem.init(pushed:))
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
}
