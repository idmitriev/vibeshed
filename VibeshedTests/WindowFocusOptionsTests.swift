import CoreGraphics
@testable import Vibeshed
import XCTest

/// The options of `window/focusWindow`'s Window parameter.
final class WindowFocusOptionsTests: XCTestCase {
    private let nvim = window(11, app: "Ghostty", title: "nvim")
    private let btop = window(12, app: "Ghostty", title: "btop", minimized: true)
    private let finder = window(13, app: "Finder", title: "")

    func testListsWindowsInOrderAndMarksMinimizedOnes() {
        let options = WindowModule.windowOptions(for: [nvim, btop, finder])
        XCTAssertEqual(options.map(\.id), ["11", "12", "13"])
        XCTAssertEqual(options.map(\.label), ["Ghostty — nvim", "Ghostty — btop", "Finder"])
        XCTAssertEqual(options.map(\.subtitle), [nil, "Minimized", nil])
    }

    /// Every window minimized (as after Minimize All Windows): each is still listed and
    /// found by its title.
    func testFindsMinimizedWindowsByTitle() {
        let minimized = [
            window(21, app: "Ghostty", title: "~", minimized: true),
            window(22, app: "Ghostty", title: "btop", minimized: true),
            window(23, app: "Ghostty", title: "nvim", minimized: true),
        ]
        let options = WindowModule.windowOptions(for: minimized)
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options.fuzzyFiltered(by: "nvim").first?.id, "23")
        XCTAssertEqual(options.fuzzyFiltered(by: "minimized").count, 3)
    }
}

private func window(_ id: Int, app: String, title: String, minimized: Bool = false) -> WindowInfo {
    let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    return WindowInfo(
        id: id, title: title, appName: app, bundleID: nil, pid: 1,
        frame: frame, screenFrame: frame, isOnScreen: !minimized, isMinimized: minimized
    )
}
