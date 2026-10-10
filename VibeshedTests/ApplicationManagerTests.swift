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

    func testFinderIsListedFromCoreServices() {
        let finder = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        XCTAssertTrue(ApplicationManager.installedAppBundleURLs().contains(finder))
    }

    func testCoreServicesAgentsAreNotListed() {
        let listed = Set(ApplicationManager.installedAppBundleURLs().map(\.path))
        for agent in ["Dock", "SystemUIServer", "ControlCenter", "loginwindow", "Spotlight"] {
            XCTAssertFalse(listed.contains("/System/Library/CoreServices/\(agent).app"), agent)
        }
    }

    func testCoreServicesAllowlistHasOnlyRegularApps() throws {
        for url in ApplicationManager.coreServicesApps where FileManager.default.fileExists(atPath: url.path) {
            let bundle = try XCTUnwrap(Bundle(url: url), url.path)
            for key in ["LSUIElement", "LSBackgroundOnly"] {
                let value = bundle.object(forInfoDictionaryKey: key)
                let isSet = (value as? NSNumber)?.boolValue ?? ((value as? NSString)?.boolValue ?? false)
                XCTAssertFalse(isSet, "\(url.lastPathComponent) has \(key)")
            }
        }
    }

    func testExtraAppsFollowDirectoriesAndMissingOnesAreSkipped() throws {
        try makeApp("Apps/Top.app", bundleID: "test.top")
        try makeApp("Apps/Utilities/Nested.app", bundleID: "test.nested")
        let finder = try makeApp("CoreServices/Finder.app", bundleID: "test.finder")
        try makeApp("CoreServices/Agent.app", bundleID: "test.agent")
        let missing = root.appendingPathComponent("CoreServices/Gone.app")

        let names = ApplicationManager.installedAppBundleURLs(
            directories: [root.appendingPathComponent("Apps")],
            extraApps: [missing, finder]
        ).map(\.lastPathComponent)
        XCTAssertEqual(names, ["Top.app", "Nested.app", "Finder.app"])
    }

    func testFocusReopensOnlyAfterAnEmptyWindowQuery() {
        for frontmost in [false, true] {
            XCTAssertEqual(ApplicationManager.focusStep(windowCount: 0, isFrontmost: frontmost), .reopen)
            // A failed AX query says nothing about the app's windows.
            XCTAssertEqual(ApplicationManager.focusStep(windowCount: nil, isFrontmost: frontmost), .activate)
        }
    }

    func testFocusCyclesOnlyWhenFrontmost() {
        XCTAssertEqual(ApplicationManager.focusStep(windowCount: 1, isFrontmost: true), .cycleWindows)
        XCTAssertEqual(ApplicationManager.focusStep(windowCount: 2, isFrontmost: false), .restoreAndActivate)
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
