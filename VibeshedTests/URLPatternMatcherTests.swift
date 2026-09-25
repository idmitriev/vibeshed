@testable import Vibeshed
import XCTest

final class URLPatternMatcherTests: XCTestCase {
    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    func testGlobMatchesPathWildcard() {
        XCTAssertTrue(
            URLPatternMatcher.matches(
                url: url("https://github.com/anthropics/apps"),
                pattern: "https://github.com/*"
            )
        )
    }

    func testGlobRejectsDifferentHost() {
        XCTAssertFalse(
            URLPatternMatcher.matches(
                url: url("https://gitlab.com/x"),
                pattern: "https://github.com/*"
            )
        )
    }

    func testGlobLeadingAndTrailingWildcard() {
        XCTAssertTrue(
            URLPatternMatcher.matches(
                url: url("https://www.example.com/page"),
                pattern: "*example.com*"
            )
        )
    }

    func testRegexSubstringMatch() {
        XCTAssertTrue(
            URLPatternMatcher.matches(
                url: url("https://github.com/x"),
                pattern: #"/github\.com/"#
            )
        )
    }

    func testRegexAnchored() {
        XCTAssertFalse(
            URLPatternMatcher.matches(
                url: url("http://x.com"),
                pattern: "/^https:/"
            )
        )
    }

    func testInvalidRegexDoesNotMatch() {
        XCTAssertFalse(
            URLPatternMatcher.matches(url: url("https://x.com"), pattern: "/[/")
        )
    }
}
