import Foundation
@testable import Vibeshed
import XCTest

final class HomebrewManagerTests: XCTestCase {
    func testParseCaskAppPathsReturnsAppTargets() {
        let json = """
        {"formulae": [], "casks": [{"token": "visual-studio-code", "artifacts": [
          {"uninstall": [{"quit": "com.microsoft.VSCode"}]},
          {"app": ["Visual Studio Code.app"], "target": "/Applications/Visual Studio Code.app"},
          {"binary": ["/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"],
           "target": "/opt/homebrew/bin/code"}
        ]}]}
        """
        XCTAssertEqual(
            HomebrewManager.parseCaskAppPaths(Data(json.utf8)),
            ["/Applications/Visual Studio Code.app"]
        )
    }

    func testParseCaskAppPathsIgnoresCasksWithoutApps() {
        let json = """
        {"casks": [{"token": "font-fira-code", "artifacts": [
          {"font": ["ttf/FiraCode-Bold.ttf"], "target": "/Users/me/Library/Fonts/FiraCode-Bold.ttf"}
        ]}]}
        """
        XCTAssertEqual(HomebrewManager.parseCaskAppPaths(Data(json.utf8)), [])
    }

    func testInstallSummaryPicksBeerLine() {
        let output = """
        ==> Fetching downloads for: jq
        ==> Pouring jq--1.7.1.arm64_sequoia.bottle.tar.gz
        🍺  /opt/homebrew/Cellar/jq/1.7.1: 19 files, 1.3MB
        ==> Running `brew cleanup jq`...
        """
        XCTAssertEqual(HomebrewManager.installSummary(output), "/opt/homebrew/Cellar/jq/1.7.1: 19 files, 1.3MB")
    }

    func testInstallSummaryFallsBackToLastLine() {
        XCTAssertEqual(HomebrewManager.installSummary("==> Downloading\nall done\n"), "all done")
        XCTAssertEqual(HomebrewManager.installSummary(""), "")
    }

    func testParseCaskAppPathsHandlesMalformedJSON() {
        XCTAssertEqual(HomebrewManager.parseCaskAppPaths(Data("Error: no such cask".utf8)), [])
    }
}
