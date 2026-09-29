@testable import Vibeshed
import XCTest

/// End-to-end `provideActions` behavior for the query-dependent WebSearch module
/// (using its default config).
final class QueryDependentModuleTests: XCTestCase {
    private let scoring = ScoringContext(
        usageCounts: [:], lastUsedDates: [:], query: "", systemContext: nil
    )

    func testWebSearchReturnsOneActionPerEngine() async {
        let module = WebSearchModule()
        let actions = await module.provideActions(query: "hello world", scoring: scoring)
        XCTAssertEqual(actions.count, WebSearchConfig.defaultEngines.count)
        XCTAssertTrue(actions.allSatisfy { $0.title.contains("hello world") })
        XCTAssertTrue(actions.allSatisfy { $0.relevanceScore <= 0.1 }, "must sink below real matches")
    }

    func testWebSearchIgnoresShortQueries() async {
        let module = WebSearchModule()
        let actions = await module.provideActions(query: "h", scoring: scoring)
        XCTAssertTrue(actions.isEmpty)
    }
}
