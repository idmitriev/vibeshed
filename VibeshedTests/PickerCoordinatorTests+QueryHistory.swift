@testable import Vibeshed
import XCTest

/// A run picked from the search list is recorded with what was typed to find it, so
/// that query brings the action up again (`QueryHistory`).
extension PickerCoordinatorTests {
    private func makeTracked(log: RunLog) async throws -> (PickerCoordinator, PickerState, UsageTracker) {
        let (coordinator, state) = try await makeCoordinator(module: PickModule(log: log))
        let tracker = UsageTracker(
            storageURL: FileManager.default.temporaryDirectory.appendingPathComponent("usage-\(UUID().uuidString).json")
        )
        coordinator.usageTracker = tracker
        return (coordinator, state, tracker)
    }

    private func waitForUses(of id: ActionID, _ count: Int, in tracker: UsageTracker) async throws {
        for _ in 0 ..< 200 where (tracker.usageCounts[id.rawValue] ?? 0) < count {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(tracker.usageCounts[id.rawValue], count)
    }

    func testReturnRecordsTheTypedQuery() async throws {
        let (coordinator, state, tracker) = try await makeTracked(log: RunLog())
        state.query = "pi"
        await coordinator.loadInitialActions().value

        coordinator.handleReturn()

        try await waitForUses(of: PickModule.ping, 1, in: tracker)
        XCTAssertEqual(tracker.queryHistory.picks[PickModule.ping.rawValue]?.keys.sorted(), ["pi"])
    }

    /// A Shift run clears the field before the action runs; the query is read first.
    func testShiftRunRecordsTheQueryItClears() async throws {
        let (coordinator, state, tracker) = try await makeTracked(log: RunLog())
        state.query = "ping"
        await coordinator.loadInitialActions().value

        coordinator.handleReturn(keepOpen: true)

        XCTAssertEqual(state.query, "")
        try await waitForUses(of: PickModule.ping, 1, in: tracker)
        XCTAssertEqual(tracker.queryHistory.picks[PickModule.ping.rawValue]?.keys.sorted(), ["ping"])
    }

    /// What was typed in the list counts, not the text typed for its parameter.
    func testParameterRunRecordsTheListQuery() async throws {
        let log = RunLog()
        let (coordinator, state, tracker) = try await makeTracked(log: log)
        state.query = "inst"
        await coordinator.loadInitialActions().value
        XCTAssertEqual(state.selectedActionID, PickModule.install)

        coordinator.handleReturn()
        XCTAssertEqual(state.currentParameter?.id, "name")
        state.parameterQuery = "zed"
        coordinator.handleReturn()

        try await waitForUses(of: PickModule.install, 1, in: tracker)
        XCTAssertEqual(tracker.queryHistory.picks[PickModule.install.rawValue]?.keys.sorted(), ["inst"])
    }
}

/// A parameterless Ping and an Install that takes a typed name.
private actor PickModule: Module {
    static let ping = ActionID(module: "pick", name: "ping")
    static let install = ActionID(module: "pick", name: "install")

    let id = "pick"
    let displayName = "Pick"
    let iconName = "sparkle"
    var isEnabled = true
    let log: RunLog

    init(log: RunLog) {
        self.log = log
    }

    func initialize(context _: ModuleContext) async throws {}

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        [
            RecordingAction(id: Self.ping, log: log),
            RecordingAction(
                id: Self.install,
                parameters: [
                    ActionParameter(id: "name", label: "Name", type: .text(placeholder: ""), isRequired: true),
                ],
                log: log
            ),
        ]
    }
}
