@testable import Vibeshed
import XCTest

final class WebSearchModuleTests: XCTestCase {
    func testSearchURLEncodesQuery() throws {
        let url = WebSearchModule.searchURL(
            template: "https://www.google.com/search?q={query}",
            query: "swift & c++ #tips"
        )
        XCTAssertEqual(
            url?.absoluteString,
            "https://www.google.com/search?q=swift%20%26%20c%2B%2B%20%23tips"
        )
    }

    func testValidateRejectsTemplateWithoutPlaceholder() {
        var config = WebSearchConfig()
        config.engines = [
            WebSearchConfig.Engine(name: "Broken", urlTemplate: "https://example.com", iconName: nil),
        ]
        let result = WebSearchModule.validate(config)
        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.errors.contains { $0.contains("{query}") })
    }

    func testDefaultConfigIsValid() {
        XCTAssertTrue(WebSearchModule.validate(WebSearchConfig()).isValid)
    }
}
