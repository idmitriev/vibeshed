@testable import Vibeshed
import XCTest

/// Equal-score rows must rank the same on every catalog refetch. The module fan-out
/// and the browser tab listing used to collect results in completion order, so a
/// dynamic refresh reshuffled tied rows under the user whenever modules (or browsers)
/// answered in a different order.
@MainActor
final class CatalogOrderTests: XCTestCase {
    private let scoring = ScoringContext(
        usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
    )

    func testRefetchKeepsTiedRowsInPlaceWhenModulesAnswerInAnotherOrder() async throws {
        let eventBus = EventBus()
        let registry = ModuleRegistry(
            eventBus: eventBus,
            configManager: ConfigManager(eventBus: eventBus),
            permissionsManager: PermissionsManager(eventBus: eventBus)
        )
        // Registered out of ID order, and `delta` has one row that outranks the rest.
        let modules = [
            DelayedModule(id: "charlie"),
            DelayedModule(id: "alpha"),
            DelayedModule(id: "delta", topRow: true),
            DelayedModule(id: "bravo"),
        ]
        for module in modules {
            try await registry.register(module)
        }

        func rankedIDs(answeringIn order: [DelayedModule]) async -> [String] {
            for (position, module) in order.enumerated() {
                await module.setDelay(.milliseconds(40 * position))
            }
            let actions = await registry.catalogActions(scoring: scoring)
            let (items, _) = ActionScorer.scoreAndRank(
                allActions: actions, enrichments: [:], query: "", scoring: scoring
            )
            return items.map(\.id.rawValue)
        }

        let first = await rankedIDs(answeringIn: modules)
        let second = await rankedIDs(answeringIn: modules.reversed())

        XCTAssertEqual(second, first)
        // The higher score still wins; ties follow module ID, then each module's own order.
        XCTAssertEqual(first, [
            "delta/top",
            "alpha/first", "alpha/second",
            "bravo/first", "bravo/second",
            "charlie/first", "charlie/second",
            "delta/first", "delta/second",
        ])
    }

    /// The browser module lists every browser's tabs at once, and all its tabs tie.
    func testTabListingKeepsBrowserOrderWhenBrowsersAnswerInAnotherOrder() async {
        let browsers = [
            (name: "Safari", bundleID: "com.apple.Safari"),
            (name: "Broken", bundleID: "com.example.broken"),
            (name: "Chrome", bundleID: "com.google.Chrome"),
        ]

        func listedIDs(delays: [String: Duration]) async -> [String] {
            let tabs = await BrowserManager.collectTabs(from: browsers) { browser in
                try await Task.sleep(for: delays[browser.name] ?? .zero)
                guard browser.name != "Broken" else { throw AppleScriptError.appNotRunning(browser.name) }
                return (1 ... 2).map { index in
                    TabInfo(
                        id: "\(browser.bundleID):1:\(index)", title: "Tab", url: "https://example.com/\(index)",
                        windowIndex: 1, tabIndex: index,
                        browserBundleID: browser.bundleID, browserName: browser.name
                    )
                }
            }
            return tabs.map(\.id)
        }

        let first = await listedIDs(delays: ["Safari": .zero, "Chrome": .milliseconds(80)])
        let second = await listedIDs(delays: ["Safari": .milliseconds(80), "Chrome": .zero])

        XCTAssertEqual(second, first)
        XCTAssertEqual(first, [
            "com.apple.Safari:1:1", "com.apple.Safari:1:2",
            "com.google.Chrome:1:1", "com.google.Chrome:1:2",
        ])
    }
}

/// Two equal-score rows (plus an optional higher-scored one), returned after a
/// settable delay so tests control which module answers first.
private actor DelayedModule: Module {
    let id: String
    let displayName = "Delayed"
    let iconName = "clock"
    var isEnabled = true
    private let topRow: Bool
    private var delay: Duration = .zero

    init(id: String, topRow: Bool = false) {
        self.id = id
        self.topRow = topRow
    }

    func initialize(context _: ModuleContext) async throws {}

    func setDelay(_ delay: Duration) {
        self.delay = delay
    }

    func provideActions(query _: String, scoring _: ScoringContext) async -> [any Action] {
        try? await Task.sleep(for: delay)
        func row(_ name: String, relevance: Double = 0.5) -> MockAction {
            MockAction(
                id: ActionID(module: id, name: name), title: "Row", subtitle: "",
                iconName: nil, relevanceScore: relevance, keywords: []
            )
        }
        return (topRow ? [row("top", relevance: 0.9)] : []) + [row("first"), row("second")]
    }
}
