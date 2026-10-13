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
    ///
    /// `query` is what was typed to pick the action from the search list, recorded with
    /// its usage so that query brings it up again; nil when it ran some other way.
    func executeAction(
        _ action: any Action, values: ParameterValues, keepOpen: Bool = false, pickedFor query: String? = nil
    ) async {
        let keepOpen = keepOpen && !action.typesIntoFrontmostApp
        Log.picker.debug("Executing action '\(action.id, privacy: .public)', keepOpen: \(keepOpen)")
        if keepOpen {
            panelController.holdKeyFocusThroughActions()
        } else {
            panelController.close()
        }
        let run = ActionRun(keptOpen: keepOpen, presentation: panelController.presentationCount)
        do {
            let result = try await action.run(with: values)
            usageTracker?.recordUsage(actionID: action.id, query: action.isFallback ? nil : query)
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
            // picker was closed since, that was the user's doing. One the run closed
            // comes back fresh, as it would have opened next.
            if !keepOpen, !panelController.isVisible {
                panelController.show()
            }

        case let .pushActions(actions):
            let items = actions.map(ActionItem.init(pushed:))
            var cache: [ActionID: any Action] = [:]
            for action in actions {
                cache[action.id] = action
            }
            if panelController.isVisible {
                // Over the session on screen — the one a Shift run left open, or one opened
                // while the run went on: Escape goes back to it.
                pickerState.pushMode(.pushedActions)
                pickerState.updateActions(items, cache: cache)
            } else {
                // The run closed the picker, so the results are all there is to go back to.
                presentRootList(items, cache: cache)
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
            pickerState.pushMode(.pushedActions)
            pickerState.updateActions([item], cache: [message.id: message])
        } else {
            // The run closed the picker: Escape closes it again.
            presentRootList([item], cache: [message.id: message])
        }
    }

    /// Shows `items` as the only level of a fresh picker — the state a closing run left
    /// behind goes — so Escape closes the list. For lists that come up on their own: a
    /// run's results, the browser chooser.
    func presentRootList(_ items: [ActionItem], cache: [ActionID: any Action]) {
        pickerState.reset()
        clearContext()
        pickerState.showAsRoot(.pushedActions)
        pickerState.updateActions(items, cache: cache)
        // Re-presenting a picker that's still up would replay its show animation.
        if !panelController.isVisible {
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
