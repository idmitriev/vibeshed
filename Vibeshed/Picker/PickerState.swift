import Foundation
import Combine

@MainActor
@Observable
final class PickerState {
    var query: String = "" {
        didSet { querySubject.send(query) }
    }

    var actions: [ActionItem] = []
    var selectedActionID: ActionID?
    var isLoading: Bool = false

    private let querySubject = PassthroughSubject<String, Never>()

    var debouncedQuery: AnyPublisher<String, Never> {
        querySubject
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func reset() {
        query = ""
        actions = []
        selectedActionID = nil
        isLoading = false
    }

    func selectNext() {
        guard !actions.isEmpty else { return }
        guard let currentID = selectedActionID,
              let idx = actions.firstIndex(where: { $0.id == currentID }) else {
            selectedActionID = actions.first?.id
            return
        }
        let next = actions.index(after: idx)
        selectedActionID = (next < actions.endIndex) ? actions[next].id : currentID
    }

    func selectPrevious() {
        guard !actions.isEmpty else { return }
        guard let currentID = selectedActionID,
              let idx = actions.firstIndex(where: { $0.id == currentID }) else {
            selectedActionID = actions.last?.id
            return
        }
        if idx > actions.startIndex {
            selectedActionID = actions[actions.index(before: idx)].id
        }
    }
}

struct ActionItem: Identifiable, Equatable, Sendable {
    let id: ActionID
    let title: String
    let subtitle: String
    let iconSystemName: String?
    let score: Double
    let moduleID: String
}
