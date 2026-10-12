import CoreGraphics
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
        let run = ActionRun(keptOpen: keepOpen, presentation: panelController.presentationCount)
        do {
            let result = try await action.run(with: values)
            usageTracker?.recordUsage(actionID: action.id)
            await handleActionResult(result, of: action, run: run)
        } catch {
            Log.picker
                .error(
                    "Action '\(action.id, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
                )
            await showMessage(
                PickerMessageAction(
                    source: action.id,
                    title: action.title,
                    body: error.localizedDescription,
                    isFailure: true
                ),
                for: run
            )
        }
    }

    private func handleActionResult(_ result: ActionResult, of action: any Action, run: ActionRun) async {
        let keepOpen = run.keptOpen
        switch result {
        case .dismiss:
            break

        case let .showResult(title, body):
            await showMessage(
                PickerMessageAction(source: action.id, title: title, body: body, isFailure: false),
                for: run
            )

        case .keepOpen:
            // A run that kept the picker open has nothing to bring back — and if the
            // picker was closed since, that was the user's doing.
            if !keepOpen {
                panelController.showRetainingState()
            }

        case let .pushActions(actions):
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

    /// Posts a result or failure as a notification. When notifications aren't allowed,
    /// shows it as the picker's only row instead — but only while the user is still
    /// waiting on the run: the picker is as the run left it and nothing was typed or
    /// clicked since. Otherwise it would replace what they moved on to, or take keys
    /// typed into another app; it's only logged then.
    private func showMessage(_ message: PickerMessageAction, for run: ActionRun) async {
        // Checked before posting: answering the notification permission prompt is input too.
        let userActed = run.userActedSinceStart()
        guard await !postActionNotification(title: message.title, body: message.body) else { return }
        guard !userActed,
              panelController.presentationCount == run.presentation,
              panelController.isVisible == run.keptOpen
        else {
            Log.picker.notice("Not showing '\(message.title, privacy: .public)': the user moved on")
            return
        }

        let item = ActionItem(pushed: message)
        if run.keptOpen {
            // Over the session the Shift run left open: Escape goes back to it as it was.
            pickerState.pushMode(.pushedActions, restoringList: true)
            pickerState.updateActions([item], cache: [message.id: message])
        } else {
            // The picker was closed and reset: Escape closes it again.
            pickerState.showAsRoot(.pushedActions)
            pickerState.updateActions([item], cache: [message.id: message])
            panelController.showRetainingState()
        }
    }
}

/// What `executeAction` notes as a run starts, to tell later whether the user is still
/// waiting on it.
struct ActionRun {
    let keptOpen: Bool
    let presentation: Int
    let startUptime = ProcessInfo.processInfo.systemUptime

    /// Whether a key was pressed or the mouse clicked since the run started. The Return
    /// or click that started it came first, so it doesn't count.
    func userActedSinceStart() -> Bool {
        let elapsed = ProcessInfo.processInfo.systemUptime - startUptime
        let inputTypes: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown]
        return inputTypes.contains {
            CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) < elapsed
        }
    }
}
