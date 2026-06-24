@testable import Vibeshed
import XCTest

final class ActionIDTests: XCTestCase {
    func testModuleAndNameComposition() {
        let id = ActionID(module: "window", name: "cycleLeft")
        XCTAssertEqual(id.rawValue, "window/cycleLeft")
        XCTAssertEqual(id.moduleID, "window")
        XCTAssertEqual(id.actionName, "cycleLeft")
    }

    func testParsingFromRawValue() {
        let id = ActionID("application/app.com.apple.Safari")
        XCTAssertEqual(id.moduleID, "application")
        XCTAssertEqual(id.actionName, "app.com.apple.Safari")
    }

    func testActionNameKeepsTrailingSeparators() {
        // Only the first "/" separates module from name.
        let id = ActionID("alias/foo/bar")
        XCTAssertEqual(id.moduleID, "alias")
        XCTAssertEqual(id.actionName, "foo/bar")
    }

    func testNoSeparatorFallsBackToWholeString() {
        let id = ActionID("bareword")
        XCTAssertEqual(id.moduleID, "bareword")
        XCTAssertEqual(id.actionName, "bareword")
    }

    func testEquatableAndHashable() {
        let a = ActionID(module: "m", name: "n")
        let b = ActionID("m/n")
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }
}
