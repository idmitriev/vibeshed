@testable import Vibeshed
import XCTest

final class PermissionPlanTests: XCTestCase {
    func testAlwaysAsksForAccessibilityForTheHotkey() {
        XCTAssertEqual(PermissionPlan(required: []).permissions, [.accessibility])
    }

    /// Dialogs answered in place come before the grants after which macOS may offer
    /// to quit and reopen Vibeshed.
    func testOrdersTheStepsSoARelaunchComesLast() {
        let plan = PermissionPlan(
            required: [.screenRecording, .fullDiskAccess, .accessibility],
            optional: [.calendars],
            automationTargets: ["com.spotify.client"],
            usesCapsLock: true
        )
        XCTAssertEqual(
            plan.permissions,
            [.accessibility, .automation, .calendars, .fullDiskAccess, .inputMonitoring, .screenRecording]
        )
    }

    func testAsksForInputMonitoringOnlyForCapsLockBindings() {
        XCTAssertFalse(PermissionPlan(required: []).permissions.contains(.inputMonitoring))
        XCTAssertTrue(PermissionPlan(required: [], usesCapsLock: true).permissions.contains(.inputMonitoring))
    }

    func testAsksForAutomationOnlyWhenModulesScriptApps() {
        XCTAssertFalse(PermissionPlan(required: []).permissions.contains(.automation))
        let scripting = PermissionPlan(required: [], automationTargets: ["com.apple.Safari"])
        XCTAssertTrue(scripting.permissions.contains(.automation))
    }

    func testAsksAboutSystemEventsFirstThenAppleApps() {
        let plan = PermissionPlan(
            required: [],
            automationTargets: [
                "com.spotify.client", "com.apple.Safari", AutomationConsent.systemEvents, AutomationConsent.finder,
            ]
        )
        XCTAssertEqual(
            plan.automationTargets,
            [AutomationConsent.systemEvents, AutomationConsent.finder, "com.apple.Safari", "com.spotify.client"]
        )
    }

    /// What the first-launch config's built-in modules need from macOS.
    func testBuiltInModulesNeedScreenRecordingAndAutomation() async {
        let modules: [any Module] = [WindowModule(), ClipboardModule(), ThemeModule(), SystemModule()]
        var targets = Set<String>()
        for module in modules {
            await targets.formUnion(module.automationTargets)
        }
        let types = modules.map { type(of: $0) }
        let plan = PermissionPlan(
            required: Set(types.flatMap { $0.requiredPermissions }),
            optional: Set(types.flatMap { $0.optionalPermissions }),
            automationTargets: targets
        )
        XCTAssertEqual(plan.permissions, [.accessibility, .automation, .screenRecording])
        XCTAssertEqual(plan.automationTargets.first, AutomationConsent.systemEvents)
    }

    func testRecognizesCapsLockBindings() {
        XCTAssertTrue(KeyBindingEntry(combo: "capslock+space", action: "app/togglePicker").usesCapsLock)
        XCTAssertTrue(KeyBindingEntry(combo: "capslock+h", remap: "left").usesCapsLock)
        XCTAssertFalse(KeyBindingEntry(combo: "option+space", action: "app/togglePicker").usesCapsLock)
        XCTAssertFalse(KeyBindingEntry(combo: "not a combo", action: "app/togglePicker").usesCapsLock)
    }
}
