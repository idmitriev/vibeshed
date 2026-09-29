import AppKit
@testable import Vibeshed
import XCTest

final class ClipboardPrivacyTests: XCTestCase {
    /// Password managers mark what they copy (nspasteboard.org); history must not keep it.
    func testSkipsWhatAppsMarkPrivate() {
        let markers = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.agilebits.onepassword"]
        for marker in markers {
            XCTAssertFalse(ClipboardManager.shouldRecord(types: [.string, .init(marker)]), marker)
        }
    }

    func testRecordsOrdinaryCopies() {
        XCTAssertTrue(ClipboardManager.shouldRecord(types: [.string]))
        XCTAssertTrue(ClipboardManager.shouldRecord(types: [.string, .rtf, .URL]))
        XCTAssertTrue(ClipboardManager.shouldRecord(types: nil))
    }
}
