import AppKit
@testable import Vibeshed
import XCTest

/// Pins the stacking of Vibeshed's own windows. The focus border is ordered front whenever
/// it reappears, so it has to sit on a lower level than anything Vibeshed draws over apps:
/// sharing the picker's level once put the ring across the open picker.
@MainActor
final class WindowLevelTests: XCTestCase {
    func testFocusBorderIsAboveOrdinaryWindows() {
        XCTAssertGreaterThan(NSWindow.Level.focusBorder.rawValue, NSWindow.Level.normal.rawValue)
    }

    func testFocusBorderIsBelowEverythingDrawnOverApps() {
        let above: [NSWindow.Level] = [.picker, .pickerOverlay, .pickerAboveOverlay, .keystrokeVisualizer]
        for level in above {
            XCTAssertLessThan(NSWindow.Level.focusBorder.rawValue, level.rawValue, "\(level.rawValue)")
        }
    }

    func testPickerIsAboveItsOverlay() {
        XCTAssertGreaterThan(NSWindow.Level.pickerAboveOverlay.rawValue, NSWindow.Level.pickerOverlay.rawValue)
        XCTAssertLessThan(NSWindow.Level.pickerAboveOverlay.rawValue, NSWindow.Level.keystrokeVisualizer.rawValue)
    }

    func testWindowsStartAtTheirLevels() {
        XCTAssertEqual(FocusBorderPanel().level, .focusBorder)
        XCTAssertEqual(FloatingPanel(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300)).level, .picker)
        XCTAssertEqual(OverlayWindow().level, .pickerOverlay)
    }
}
