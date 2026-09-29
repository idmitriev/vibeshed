@testable import Vibeshed
import XCTest

/// `[ParameterOption].fuzzyFiltered` ranks options like actions: label, subtitle
/// and keywords all count.
final class ParameterOptionFilterTests: XCTestCase {
    func testMatchesKeywordsAndSubtitles() {
        let options = [
            ParameterOption(id: "subtitle", label: "Orange", subtitle: "Carrot juice"),
            ParameterOption(id: "label", label: "Carrot"),
            ParameterOption(id: "keyword", label: "Automobile", keywords: ["car"]),
            ParameterOption(id: "none", label: "Banana"),
        ]
        let ids = options.fuzzyFiltered(by: "car").map(\.id)
        // An exact keyword is a deliberate synonym, so it beats a partial label match.
        XCTAssertEqual(ids, ["keyword", "label", "subtitle"])
    }

    func testHighlightsLabelMatchesOnly() {
        let options = [
            ParameterOption(id: "label", label: "Carrot"),
            ParameterOption(id: "keyword", label: "Automobile", keywords: ["car"]),
        ]
        let filtered = options.fuzzyFiltered(by: "car")
        XCTAssertNotNil(filtered.first { $0.id == "label" }?.labelHighlightRanges)
        XCTAssertNil(filtered.first { $0.id == "keyword" }?.labelHighlightRanges)
    }

    func testTiesKeepModuleOrder() {
        let options = ["b", "a", "c"].map { ParameterOption(id: $0, label: "Same", keywords: []) }
        XCTAssertEqual(options.fuzzyFiltered(by: "same").map(\.id), ["b", "a", "c"])
    }
}
