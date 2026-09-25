import Foundation

/// A live preview in progress: the parameter being browsed and the last option
/// reported to its module.
struct LivePreviewSession {
    let actionID: ActionID
    let parameterID: String
    var lastOptionID: String?
}

/// Live parameter preview: while the picker collects a parameter declared with
/// `livePreview: true`, each highlighted option is reported (debounced) to the owning
/// module, which applies it for real. Return commits it; Escape, backing out of the
/// parameter, or dismissing the picker ends the preview uncommitted so the module
/// can revert.
extension PickerCoordinator {
    static let livePreviewDelay: Duration = .milliseconds(160)

    /// Re-evaluates the preview after a mode, selection, or visibility change.
    func syncLivePreview() {
        let target = livePreviewTarget()
        if let session = livePreview,
           target?.actionID != session.actionID || target?.parameter.id != session.parameterID
        {
            _ = endLivePreview(committed: false)
        }
        guard let target else { return }

        if livePreview == nil {
            livePreview = LivePreviewSession(actionID: target.actionID, parameterID: target.parameter.id)
        }
        guard let optionID = pickerState.selectedParameterOptionID,
              optionID != livePreview?.lastOptionID
        else { return }
        livePreview?.lastOptionID = optionID

        livePreviewTask?.cancel()
        let module = moduleRegistry.module(id: target.actionID.moduleID)
        let parameterID = target.parameter.id
        let actionID = target.actionID
        livePreviewTask = Task {
            try? await Task.sleep(for: Self.livePreviewDelay)
            guard !Task.isCancelled else { return }
            await module?.previewParameterOption(optionID, parameterID: parameterID, actionID: actionID)
        }
    }

    /// Ends the current preview, if any. Returns the task delivering the end to the
    /// module so a commit can be ordered before the action runs.
    func endLivePreview(committed: Bool) -> Task<Void, Never>? {
        guard let session = livePreview else { return nil }
        livePreview = nil
        livePreviewTask?.cancel()
        livePreviewTask = nil
        let module = moduleRegistry.module(id: session.actionID.moduleID)
        return Task {
            await module?.endParameterPreview(
                parameterID: session.parameterID,
                actionID: session.actionID,
                committed: committed
            )
        }
    }

    private func livePreviewTarget() -> (actionID: ActionID, parameter: ActionParameter)? {
        guard panelController.isVisible,
              case let .parameterInput(actionID, _) = pickerState.mode,
              let parameter = pickerState.currentParameter,
              parameter.livePreview
        else { return nil }
        return (actionID, parameter)
    }
}
