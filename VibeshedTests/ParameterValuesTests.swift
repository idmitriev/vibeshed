@testable import Vibeshed
import XCTest

final class ParameterValuesTests: XCTestCase {
    func testDictionaryLiteralAndSubscript() {
        var values: ParameterValues = ["path": "/tmp", "name": "x"]
        XCTAssertEqual(values["path"], "/tmp")
        XCTAssertNil(values["missing"])
        values["name"] = "y"
        XCTAssertEqual(values["name"], "y")
    }

    func testEmpty() {
        XCTAssertTrue(ParameterValues.empty.isEmpty)
        XCTAssertTrue(ParameterValues().isEmpty)
        XCTAssertFalse((["a": "b"] as ParameterValues).isEmpty)
    }

    func testTypedAccessors() {
        let values: ParameterValues = [
            "count": "42",
            "ratio": "1.5",
            "flagOn": "true",
            "flagOff": "false",
            "text": "hello",
        ]
        XCTAssertEqual(values.int("count"), 42)
        XCTAssertEqual(values.double("ratio"), 1.5)
        XCTAssertEqual(values.bool("flagOn"), true)
        XCTAssertEqual(values.bool("flagOff"), false)
        XCTAssertEqual(values.string("text"), "hello")
    }

    func testTypedAccessorsReturnNilForMissingOrUnparseable() {
        let values: ParameterValues = ["text": "notanumber"]
        XCTAssertNil(values.int("text"))
        XCTAssertNil(values.double("text"))
        XCTAssertNil(values.int("missing"))
    }

    func testBoolTreatsNonTrueAsFalse() {
        let values: ParameterValues = ["x": "TRUE"]
        // Only the exact lowercase "true" is true.
        XCTAssertEqual(values.bool("x"), false)
        XCTAssertEqual(values.bool("missing"), false)
    }

    func testRawRoundTrip() {
        let dict = ["a": "1", "b": "2"]
        let values = ParameterValues(dict)
        XCTAssertEqual(values.raw, dict)
    }

    func testEquatable() {
        XCTAssertEqual(ParameterValues(["a": "1"]), ["a": "1"] as ParameterValues)
        XCTAssertNotEqual(ParameterValues(["a": "1"]), ["a": "2"] as ParameterValues)
    }
}
