@testable import Vibeshed
import XCTest

@MainActor
final class PermissionWalkthroughTests: XCTestCase {
    private let everything = PermissionPlan(
        required: [.screenRecording, .fullDiskAccess],
        automationTargets: [AutomationConsent.systemEvents, "com.spotify.client"]
    )

    func testAsksForEachMissingPermissionInOrder() async {
        let authority = FakeAuthority(grantsOnRequest: Set(Permission.allCases))
        let walkthrough = makeWalkthrough(everything, authority)

        walkthrough.start()
        await waitUntil { !walkthrough.isRunning }

        XCTAssertEqual(authority.requested, [.accessibility, .automation, .fullDiskAccess, .screenRecording])
        XCTAssertEqual(authority.automationAsked, [[AutomationConsent.systemEvents, "com.spotify.client"]])
        XCTAssertTrue(walkthrough.allGranted)
        XCTAssertNil(walkthrough.current)
    }

    func testLeavesOutWhatIsAlreadyGranted() async {
        let authority = FakeAuthority(
            granted: [.accessibility, .fullDiskAccess],
            grantsOnRequest: Set(Permission.allCases)
        )
        let walkthrough = makeWalkthrough(everything, authority)

        walkthrough.start()
        await waitUntil { !walkthrough.isRunning }

        XCTAssertEqual(authority.requested, [.automation, .screenRecording])
    }

    /// Screen Recording is granted with a switch in System Settings: the walkthrough
    /// waits for it, then comes back to the front.
    func testWaitsForTheSwitchInSystemSettings() async {
        let authority = FakeAuthority(granted: [.accessibility, .automation, .fullDiskAccess])
        let walkthrough = makeWalkthrough(everything, authority)
        var broughtBack: [Permission] = []
        walkthrough.onGrantedInSettings = { broughtBack.append($0) }

        walkthrough.start()
        await waitUntil { walkthrough.current == .screenRecording }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(walkthrough.isRunning, "moved on before the switch was flipped")

        authority.granted.insert(.screenRecording)
        await waitUntil { !walkthrough.isRunning }
        XCTAssertEqual(broughtBack, [.screenRecording])
        XCTAssertTrue(walkthrough.allGranted)
    }

    func testSkipMovesOnToTheNextPermission() async {
        let authority = FakeAuthority(granted: [.accessibility, .automation])
        let walkthrough = makeWalkthrough(everything, authority)

        walkthrough.start()
        await waitUntil { walkthrough.current == .fullDiskAccess }
        walkthrough.skip()
        await waitUntil { walkthrough.current == .screenRecording }
        walkthrough.skip()
        await waitUntil { !walkthrough.isRunning }

        XCTAssertEqual(authority.requested, [.fullDiskAccess, .screenRecording])
        XCTAssertEqual(walkthrough.skipped, [.fullDiskAccess, .screenRecording])
        XCTAssertFalse(walkthrough.allGranted)

        walkthrough.start([.fullDiskAccess])
        XCTAssertEqual(walkthrough.skipped, [.screenRecording], "trying again clears the skip")
        walkthrough.cancel()
    }

    /// Automation is answered in macOS's own dialog: a "Don't Allow" doesn't hold the
    /// walkthrough up.
    func testDoesNotWaitOnDialogsAnsweredInPlace() async {
        let authority = FakeAuthority(granted: [.accessibility], grantsOnRequest: [.fullDiskAccess, .screenRecording])
        let walkthrough = makeWalkthrough(everything, authority)

        walkthrough.start()
        await waitUntil { !walkthrough.isRunning }

        XCTAssertEqual(authority.requested, [.automation, .fullDiskAccess, .screenRecording])
        XCTAssertFalse(walkthrough.isGranted(.automation))
        XCTAssertTrue(walkthrough.skipped.isEmpty)
    }

    func testCancelStopsBeforeTheNextPermission() async {
        let authority = FakeAuthority(granted: [.accessibility, .automation])
        let walkthrough = makeWalkthrough(everything, authority)

        walkthrough.start()
        await waitUntil { walkthrough.current == .fullDiskAccess }
        walkthrough.cancel()
        await waitUntil { !walkthrough.isRunning }

        XCTAssertEqual(authority.requested, [.fullDiskAccess])
    }

    func testPickerHotkeyLabel() {
        func label(_ combo: String) -> String? {
            PermissionSetup.pickerHotkey(in: [KeyBindingEntry(combo: combo, action: "app/togglePicker")])
        }
        XCTAssertEqual(label("option+space"), "⌥Space")
        XCTAssertEqual(label("capslock+space"), "⇪Space")
        XCTAssertEqual(label("cmd+shift+k"), "⇧⌘K")
        let otherAction = KeyBindingEntry(combo: "option+space", action: "window/center")
        XCTAssertNil(PermissionSetup.pickerHotkey(in: [otherAction]))
    }

    // MARK: - Helpers

    private func makeWalkthrough(_ plan: PermissionPlan, _ authority: FakeAuthority) -> PermissionWalkthrough {
        PermissionWalkthrough(plan: plan, authority: authority, pollInterval: .milliseconds(5))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                return XCTFail("Timed out", file: file, line: line)
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Grants what's in `grantsOnRequest` as soon as it's asked for, like clicking Allow
/// or flipping the switch straight away; the rest stays missing until a test grants it.
@MainActor
private final class FakeAuthority: PermissionAuthority {
    var granted: Set<Permission>
    let grantsOnRequest: Set<Permission>
    private(set) var requested: [Permission] = []
    private(set) var automationAsked: [[String]] = []

    init(granted: Set<Permission> = [], grantsOnRequest: Set<Permission> = []) {
        self.granted = granted
        self.grantsOnRequest = grantsOnRequest
    }

    func isGranted(_ permission: Permission) -> Bool {
        granted.contains(permission)
    }

    func refresh(_: Permission) {}

    func request(_ permission: Permission) async {
        requested.append(permission)
        if grantsOnRequest.contains(permission) {
            granted.insert(permission)
        }
    }

    func requestAutomation(for bundleIDs: [String]) async -> [String: AutomationConsent.Status] {
        automationAsked.append(bundleIDs)
        await request(.automation)
        return [:]
    }

    func openSettings(for _: Permission) {}
}
