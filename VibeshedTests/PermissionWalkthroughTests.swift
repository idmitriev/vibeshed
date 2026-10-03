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
        let authority = FakeAuthority(granted: [.accessibility, .fullDiskAccess], automation: allowed)
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
        let authority = FakeAuthority(granted: [.accessibility], automation: allowed)
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
        let authority = FakeAuthority(granted: [.accessibility], automation: allowed)
        let walkthrough = makeWalkthrough(everything, authority)

        walkthrough.start()
        await waitUntil { walkthrough.current == .fullDiskAccess }
        walkthrough.cancel()
        await waitUntil { !walkthrough.isRunning }

        XCTAssertEqual(authority.requested, [.fullDiskAccess])
    }

    /// Every app in the plan counts: one refusal keeps Automation open, and the row can
    /// say which app it was.
    func testAutomationGoesByEachAppInThePlan() {
        let authority = FakeAuthority(automation: [
            AutomationConsent.systemEvents: .allowed, "com.spotify.client": .denied,
        ])
        let walkthrough = makeWalkthrough(everything, authority)
        XCTAssertFalse(walkthrough.isGranted(.automation))
        XCTAssertEqual(walkthrough.deniedAutomationTargets, ["com.spotify.client"])
    }

    /// A plan without System Events is done once its own apps allow it.
    func testPlanWithoutSystemEventsIsDoneWhenItsAppsAllow() {
        let plan = PermissionPlan(required: [], automationTargets: ["com.spotify.client"])
        let allowed = makeWalkthrough(plan, FakeAuthority(automation: ["com.spotify.client": .allowed]))
        XCTAssertTrue(allowed.isGranted(.automation))
        let unasked = makeWalkthrough(plan, FakeAuthority(automation: ["com.spotify.client": .notAsked]))
        XCTAssertFalse(unasked.isGranted(.automation))
    }

    /// Apps that haven't run can't be asked yet, so they don't hold Automation up.
    /// System Events can be started just to ask, so it has to answer.
    func testAppsThatHaventRunDontHoldItUpButSystemEventsDoes() {
        let nothingRunning = FakeAuthority(automation: [
            AutomationConsent.systemEvents: .notRunning, "com.spotify.client": .notRunning,
        ])
        XCTAssertEqual(makeWalkthrough(everything, nothingRunning).automationHoldouts, [AutomationConsent.systemEvents])

        let systemEventsAnswered = FakeAuthority(automation: [AutomationConsent.systemEvents: .allowed])
        XCTAssertTrue(makeWalkthrough(everything, systemEventsAnswered).isGranted(.automation))
    }

    func testPickerHotkeyLabel() {
        func label(_ combo: String) -> String? {
            PermissionSetup.pickerHotkey(in: [KeyBindingEntry(combo: combo, action: "app/togglePicker")])
        }
        XCTAssertEqual(label("option+space"), "⌥Space")
        XCTAssertEqual(label("capslock+space"), "Caps Lock + Space")
        XCTAssertEqual(label("cmd+shift+k"), "⇧⌘K")
        let otherAction = KeyBindingEntry(combo: "option+space", action: "window/center")
        XCTAssertNil(PermissionSetup.pickerHotkey(in: [otherAction]))
    }

    // MARK: - Helpers

    /// Every app in `everything` allowed already.
    private var allowed: [String: AutomationConsent.Status] {
        Dictionary(uniqueKeysWithValues: everything.automationTargets.map { ($0, .allowed) })
    }

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
/// Automation is per app: asking allows every app if `grantsOnRequest` has it, and
/// refuses them otherwise.
@MainActor
private final class FakeAuthority: PermissionAuthority {
    var granted: Set<Permission>
    private(set) var automationStatuses: [String: AutomationConsent.Status]
    let grantsOnRequest: Set<Permission>
    private(set) var requested: [Permission] = []
    private(set) var automationAsked: [[String]] = []

    init(
        granted: Set<Permission> = [],
        automation: [String: AutomationConsent.Status] = [:],
        grantsOnRequest: Set<Permission> = []
    ) {
        self.granted = granted
        automationStatuses = automation
        self.grantsOnRequest = grantsOnRequest
    }

    func isGranted(_ permission: Permission) -> Bool {
        granted.contains(permission)
    }

    func refresh(_: Permission) {}

    func refreshAutomation(for _: [String]) {}

    func request(_ permission: Permission) async {
        requested.append(permission)
        if grantsOnRequest.contains(permission) {
            granted.insert(permission)
        }
    }

    func requestAutomation(for bundleIDs: [String]) async -> [String: AutomationConsent.Status] {
        requested.append(.automation)
        automationAsked.append(bundleIDs)
        let answer: AutomationConsent.Status = grantsOnRequest.contains(.automation) ? .allowed : .denied
        for bundleID in bundleIDs {
            automationStatuses[bundleID] = answer
        }
        return automationStatuses
    }

    func openSettings(for _: Permission) {}
}
