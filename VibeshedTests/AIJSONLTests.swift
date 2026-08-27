import Foundation
@testable import Vibeshed
import XCTest

final class AIJSONLTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ contents: String, name: String = "f.jsonl") throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    func testSkipsBlankAndMalformedLines() throws {
        let path = try write(
            """
            {"a":1}

            not json
            {"b":2}
            """
        )
        let objects = AIJSONL.objects(atPath: path)
        XCTAssertEqual(objects.count, 2)
        XCTAssertEqual(objects.first?["a"] as? Int, 1)
    }

    func testMissingFileReturnsEmpty() {
        XCTAssertTrue(AIJSONL.objects(atPath: "/no/such/file.jsonl").isEmpty)
        XCTAssertTrue(
            AIJSONL.headObjects(atPath: "/no/such/file.jsonl", limit: 4).isEmpty
        )
    }

    /// The 256KB head read can land inside a multi-byte character. Decoding a chunk
    /// with a split character yields nil for the *whole* chunk, which would drop the
    /// complete records that preceded it — so the reader must cut back to the last
    /// newline. Here the header record is small and a following oversized record of
    /// multi-byte characters straddles the boundary: the header must still parse.
    func testHeadReadKeepsCompleteRecordsWhenBoundarySplitsCharacter() throws {
        let cap = 256 * 1024
        let header = #"{"type":"session_meta","cwd":"/tmp"}"#
        let recordOpening = #"{"type":"padding","pad":""#

        // Pad with ASCII so the 4-byte characters that follow start at an offset
        // where the read boundary is guaranteed to land two bytes into one of them,
        // rather than on a character edge.
        let bytesBeforePadding = header.utf8.count + 1 + recordOpening.utf8.count
        let alignment = (((cap - bytesBeforePadding - 2) % 4) + 4) % 4
        let asciiFiller = String(repeating: "x", count: alignment)
        // Comfortably past the cap, so the read stops inside this record.
        let padding = String(repeating: "🙂", count: 80_000)

        let path = try write(
            """
            \(header)
            \(recordOpening)\(asciiFiller)\(padding)"}

            """
        )
        let objects = AIJSONL.headObjects(atPath: path, limit: 8)
        XCTAssertEqual(
            objects.count, 1,
            "The complete header record must survive a truncated successor"
        )
        XCTAssertEqual(objects.first?["cwd"] as? String, "/tmp")
    }

    func testHeadReadParsesRecordsWithinChunk() throws {
        let path = try write(
            """
            {"type":"session_meta","cwd":"/tmp"}
            {"type":"turn_context","model":"gpt-5"}
            {"type":"event"}

            """
        )
        let objects = AIJSONL.headObjects(atPath: path, limit: 2)
        XCTAssertEqual(objects.count, 2)
        XCTAssertEqual(objects[0]["type"] as? String, "session_meta")
        XCTAssertEqual(objects[1]["type"] as? String, "turn_context")
    }

    func testAsSessionTitleTrimsAndTruncates() {
        XCTAssertNil("   ".asSessionTitle())
        XCTAssertEqual("  hello  ".asSessionTitle(), "hello")
        XCTAssertEqual(
            String(repeating: "a", count: 200).asSessionTitle(limit: 10),
            String(repeating: "a", count: 10)
        )
    }
}
