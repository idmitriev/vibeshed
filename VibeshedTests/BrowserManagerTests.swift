@testable import Vibeshed
import XCTest

/// A focus script must only use terms from the target browser's own dictionary: one
/// unknown term fails the whole script, and the tab never switches.
final class BrowserManagerTests: XCTestCase {
    func testChromiumFocusUsesChromiumMinimizedTerm() {
        let script = BrowserManager().chromiumFocusScript(bundleID: "com.google.Chrome", windowIndex: 2, tabIndex: 3)

        // Chrome has `minimized`; the standard suite's `miniaturized` fails with -1700.
        XCTAssertTrue(script.contains("if minimized of w then set minimized of w to false"))
        XCTAssertFalse(script.contains("miniaturized"))
        XCTAssertTrue(script.contains("set w to window 2"))
        XCTAssertTrue(script.contains("set active tab index of w to 3"))
    }

    func testArcFocusSelectsTabWithoutActiveTabIndex() {
        let script = BrowserManager().chromiumFocusScript(
            bundleID: "company.thebrowser.Browser",
            windowIndex: 1,
            tabIndex: 4
        )

        // Arc has no `active tab index`: using it is a compile error, which `try` can't catch.
        XCTAssertTrue(script.contains("tell tab 4 of w to select"))
        XCTAssertFalse(script.contains("active tab index"))
    }
}
