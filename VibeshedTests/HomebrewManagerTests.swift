import Foundation
@testable import Vibeshed
import XCTest

final class HomebrewManagerTests: XCTestCase {
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

    // MARK: - Search ranking

    func testRankSearchResultsPutsExactThenPrefixThenWordStartMatchesFirst() {
        // `brew search go` lists 250+ names alphabetically; `go` itself comes 81st.
        let names = ["algol68g", "anycable-go", "argo", "go", "go@1.24", "gopls"]
        XCTAssertEqual(
            HomebrewManager.rankSearchResults(names, query: "go"),
            ["go", "gopls", "go@1.24", "anycable-go", "argo", "algol68g"]
        )
    }

    func testRankSearchResultsIgnoresCaseAndTapPrefix() {
        let names = ["terraform-docs", "hashicorp/tap/terraform", "terraformer"]
        XCTAssertEqual(
            HomebrewManager.rankSearchResults(names, query: "Terraform"),
            ["hashicorp/tap/terraform", "terraformer", "terraform-docs"]
        )
    }

    func testRankSearchResultsKeepsBrewOrderForEqualMatches() {
        XCTAssertEqual(
            HomebrewManager.rankSearchResults(["b-tool", "a-tool", "tools"], query: "tool"),
            ["tools", "b-tool", "a-tool"]
        )
    }
}
