import Foundation
import OSLog
@testable import Vibeshed
import XCTest

final class CLILauncherTests: XCTestCase {
    private let log = Logger(subsystem: "test", category: "cli")

    func testPrefersExecutableCustomPath() {
        // /bin/sh is reliably executable on macOS.
        let resolved = CLILauncher.resolveCLI(
            customPath: "/bin/sh", candidates: ["/bin/zsh"], log: log
        )
        XCTAssertEqual(resolved, "/bin/sh")
    }

    func testNonExecutableCustomPathReturnsNilWithoutFallingBack() {
        // A custom path that isn't executable should NOT silently fall through to
        // candidates — the user asked for a specific binary.
        let resolved = CLILauncher.resolveCLI(
            customPath: "/no/such/binary", candidates: ["/bin/sh"], log: log
        )
        XCTAssertNil(resolved)
    }

    func testFallsBackToFirstExecutableCandidate() {
        let resolved = CLILauncher.resolveCLI(
            customPath: nil,
            candidates: ["/no/such/binary", "/bin/sh", "/bin/zsh"],
            log: log
        )
        XCTAssertEqual(resolved, "/bin/sh")
    }

    func testReturnsNilWhenNoCandidateExists() {
        let resolved = CLILauncher.resolveCLI(
            customPath: nil, candidates: ["/no/a", "/no/b"], log: log
        )
        XCTAssertNil(resolved)
    }
}
