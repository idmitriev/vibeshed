@testable import Vibeshed
import XCTest

final class ApplicationManagerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ApplicationManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testUserApplicationsIsSearchedByDefault() {
        let userApps = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        XCTAssertTrue(ApplicationManager.applicationDirectories.contains(userApps))
    }

    func testFindsTopLevelAndOneLevelNestedBundles() throws {
        try makeApp("Top.app", bundleID: "test.top")
        try makeApp("Chrome Apps.localized/Web.app", bundleID: "test.web")
        try makeApp("Vendor/Deep/TooDeep.app", bundleID: "test.deep")
        try makeApp(".Hidden/Secret.app", bundleID: "test.secret")
        try makeApp("Top.app/Contents/Helpers/Helper.app", bundleID: "test.helper")

        let names = ApplicationManager.appBundleURLs(in: root).map(\.lastPathComponent)
        XCTAssertEqual(names, ["Top.app", "Web.app"])
    }

    func testBundleWithoutIdentifierFallsBackToPath() throws {
        let url = try makeApp("Shortcut.app", bundleID: nil)
        let bundle = try XCTUnwrap(Bundle(url: url))
        XCTAssertEqual(ApplicationManager.appID(for: bundle), bundle.bundleURL.path)
    }

    @discardableResult
    private func makeApp(_ relativePath: String, bundleID: String?) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundlePackageType": "APPL"]
        plist["CFBundleIdentifier"] = bundleID
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }
}
