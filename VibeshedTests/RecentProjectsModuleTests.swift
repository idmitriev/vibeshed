import Foundation
import XCTest

@testable import Vibeshed

/// Exercises the generic `RecentProjectsModule` logic (ID derivation, ranked scoring,
/// enabledActions filtering, caching) via a stub provider — independent of the real
/// SQLite/XML discovery in the editor providers.
private struct StubConfig: Codable, Sendable, Equatable {
    var enabled: Set<String>?
}

private struct StubProvider: RecentProjectsProvider {
    typealias Config = StubConfig

    static let moduleID = "stub"
    static let displayName = "Stub"
    static let iconName = "questionmark"
    static var defaultConfig: StubConfig { .init() }

    func enabledActions(_ config: StubConfig) -> Set<String>? { config.enabled }

    func makeItems(config _: StubConfig) -> [RecentProjectItem] {
        ["/a/one", "/b/two", "/c/three"].map { path in
            RecentProjectItem(
                stableInput: path,
                title: (path as NSString).lastPathComponent,
                subtitle: path,
                isOpen: false,
                listIcon: "folder",
                accent: .blue,
                open: {}
            )
        }
    }
}

final class RecentProjectsModuleTests: XCTestCase {
    func testIdentityFromProvider() async {
        let module = RecentProjectsModule<StubProvider>()
        let id = await module.id
        let name = await module.displayName
        XCTAssertEqual(id, "stub")
        XCTAssertEqual(name, "Stub")
    }

    func testActionsUseStableHashedIDsAndRankedScores() async {
        let module = RecentProjectsModule<StubProvider>()
        let actions = await module.provideActions(query: "", scoring: emptyScoring)

        XCTAssertEqual(actions.count, 3)
        // IDs are module-scoped and derived from StableID over the stableInput.
        XCTAssertEqual(actions[0].id, ActionID("stub/project.\(StableID.hash("/a/one"))"))
        // Scores decrease by index per rankedScore().
        XCTAssertEqual(actions[0].relevanceScore, rankedScore(index: 0), accuracy: 0.0001)
        XCTAssertEqual(actions[1].relevanceScore, rankedScore(index: 1), accuracy: 0.0001)
        XCTAssertEqual(actions[2].relevanceScore, rankedScore(index: 2), accuracy: 0.0001)
    }

    func testEnabledActionsFilter() async {
        let onlyTwo = "project.\(StableID.hash("/b/two"))"
        let module = RecentProjectsModule<StubProvider>()
        await module.configDidUpdate(StubConfig(enabled: [onlyTwo]))

        let actions = await module.provideActions(query: "", scoring: emptyScoring)
        XCTAssertEqual(actions.map { $0.id.actionName }, [onlyTwo])
    }

    func testStaticValidateDelegatesToProvider() {
        // StubProvider uses the default .valid validation.
        XCTAssertTrue(RecentProjectsModule<StubProvider>.validate(StubConfig()).isValid)
    }

    private var emptyScoring: ScoringContext {
        ScoringContext(usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil)
    }
}
