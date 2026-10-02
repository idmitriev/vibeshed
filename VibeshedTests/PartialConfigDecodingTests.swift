@testable import Vibeshed
import XCTest
import Yams

/// Window and tiling sections may set only what they change; the rest keeps its default
/// instead of the whole section failing to decode.
final class PartialConfigDecodingTests: XCTestCase {
    func testWindowSectionWithOnlyPadding() throws {
        let config = try YAMLDecoder().decode(WindowConfig.self, from: "padding: { top: 4, gap: 4 }")
        XCTAssertEqual(config.padding, PaddingConfig(top: 4, gap: 4))
        XCTAssertEqual(config.horizontalStops, WindowConfig.defaultValue.horizontalStops)
        XCTAssertEqual(config.verticalStops, WindowConfig.defaultValue.verticalStops)
        XCTAssertEqual(config.enlargeShrinkStep, WindowConfig.defaultValue.enlargeShrinkStep)
        XCTAssertFalse(config.includeMinimized)
    }

    func testTilingSectionWithOnlyAGrid() throws {
        let yaml = """
        defaultGrid:
          columns: [1, 1]
          rows: [1]
        """
        let config = try YAMLDecoder().decode(TilingConfig.self, from: yaml)
        XCTAssertEqual(config.defaultGrid?.columns, [1, 1])
        XCTAssertEqual(config.defaultGrid?.rows, [1])
        XCTAssertEqual(config.displays, [])
        XCTAssertEqual(config.padding, PaddingConfig())
        XCTAssertEqual(config.autoTile, AutoTileConfig())
    }

    /// Only an empty section gets the default 2×2 grid; one that sets other keys and
    /// leaves `defaultGrid` out has none, as before.
    func testTilingSectionWithoutGridKeepsNoGrid() throws {
        let config = try YAMLDecoder().decode(TilingConfig.self, from: "padding: { gap: 8 }")
        XCTAssertNil(config.defaultGrid)
        XCTAssertEqual(config.padding.gap, 8)
    }
}
