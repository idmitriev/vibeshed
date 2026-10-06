@testable import Vibeshed
import XCTest

final class AliasEnrichmentTests: XCTestCase {
    private let actionIDs: Set<ActionID> = [ActionID("iterm/runCommand"), ActionID("system/lock")]

    func testAliasForAListedActionAddsKeywords() {
        let alias = AliasEntry(alias: "Lock", action: "system/lock")
        XCTAssertTrue(AliasManager.enriches(alias, actionIDs: actionIDs))
    }

    /// Enriching would drop the parameters, so these get entries of their own.
    func testAliasWithParametersIsItsOwnEntry() {
        let preset = AliasEntry(alias: "Top", action: "iterm/runCommand", parameters: ["command": "top"])
        XCTAssertFalse(AliasManager.enriches(preset, actionIDs: actionIDs))
        let query = AliasEntry(alias: "Run", action: "iterm/runCommand", parameters: ["command": "{query}"])
        XCTAssertFalse(AliasManager.enriches(query, actionIDs: actionIDs))
    }

    func testAliasForAnUnlistedActionURLOrFolderIsItsOwnEntry() {
        XCTAssertFalse(AliasManager.enriches(AliasEntry(alias: "X", action: "zoom/join"), actionIDs: actionIDs))
        XCTAssertFalse(AliasManager.enriches(AliasEntry(alias: "G", action: "https://x.com"), actionIDs: actionIDs))
        XCTAssertFalse(AliasManager.enriches(AliasEntry(alias: "D", action: "~/Downloads"), actionIDs: actionIDs))
    }
}
