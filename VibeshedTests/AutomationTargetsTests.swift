@testable import Vibeshed
import XCTest
import Yams

/// Modules name the apps they script under their current settings, so permission
/// setup asks only about apps the config will actually use.
final class AutomationTargetsTests: XCTestCase {
    func testBrowserModuleFollowsItsBrowserList() async {
        let module = BrowserModule()
        let everyBrowser = await module.automationTargets
        XCTAssertEqual(everyBrowser, BrowserRegistry.appleScriptCapable.map(\.bundleID))

        await module.configDidUpdate(BrowserConfig(browsers: ["safari", "firefox"]))
        let listed = await module.automationTargets
        XCTAssertEqual(listed, ["com.apple.Safari"], "Firefox's tabs can't be scripted")
    }

    func testSystemModuleFollowsItsEnabledActions() async {
        let module = SystemModule()
        let everything = await module.automationTargets
        XCTAssertEqual(everything, [AutomationConsent.systemEvents, AutomationConsent.finder])

        await module.configDidUpdate(SystemConfig(enabledActions: ["lock", "emptyTrash"]))
        let trashOnly = await module.automationTargets
        XCTAssertEqual(trashOnly, [AutomationConsent.finder])

        await module.configDidUpdate(SystemConfig(enabledActions: ["lock", "sleep"]))
        let none = await module.automationTargets
        XCTAssertEqual(none, [])
    }

    func testThemeModuleFollowsItsTargets() async throws {
        let module = ThemeModule()
        let defaults = await module.automationTargets
        XCTAssertEqual(defaults, [AutomationConsent.systemEvents, ITermTarget.bundleID])

        try await module.configDidUpdate(YAMLDecoder().decode(ThemeConfig.self, from: "targets: [wallpaper, vscode]"))
        let unscripted = await module.automationTargets
        XCTAssertEqual(unscripted, [])
    }

    func testAIModulesScriptTheConfiguredTerminal() {
        XCTAssertEqual(AILaunch.terminalBundleID(for: "terminal"), "com.apple.Terminal")
        XCTAssertEqual(AILaunch.terminalBundleID(for: "iterm"), ITermTarget.bundleID)
    }
}
