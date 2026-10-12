import Combine
import Foundation

// MARK: - Parameter option fetching

extension PickerCoordinator {
    func wireParameterQuery() {
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
                        pickerState.parameterOptions = options.fuzzyFiltered(by: query)
                    }
                    pickerState.selectedParameterOptionID = pickerState.parameterOptions.first?.id
                default:
                    break
                }
            }
    }

    func fetchParameterOptions(for param: ActionParameter, actionID: ActionID, query: String) {
        let moduleID = actionID.moduleID
        guard let module = moduleRegistry.module(id: moduleID) else { return }
        pickerState.isLoadingOptions = true
        parameterOptionsGeneration += 1
        let generation = parameterOptionsGeneration
        let collected = pickerState.collectedValues
        Task { @MainActor in
            let options = await module.provideParameterOptions(
                for: param.id, in: actionID, query: query, collected: collected
            )
            // Scored off the main actor: option lists can be large (~1,900 emoji).
            let filtered = await Task.detached {
                let ranked = query.isEmpty || param.rankedByModule ? options : options.fuzzyFiltered(by: query)
                return Array(ranked.prefix(ActionScorer.maxResults))
            }.value
            // Only apply the latest fetch, and only if still in the same parameter mode
            if generation == parameterOptionsGeneration,
               case let .parameterInput(currentActionID, _) = pickerState.mode,
               currentActionID == actionID,
               pickerState.currentParameter?.id == param.id
            {
                pickerState.parameterOptions = filtered
                // Open on the value in effect so a live preview starts from "no change".
                let current = query.isEmpty ? filtered.first(where: \.isCurrent) : nil
                pickerState.selectedParameterOptionID = (current ?? filtered.first)?.id
                pickerState.isLoadingOptions = false
            }
        }
    }
}
