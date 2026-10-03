import Foundation

/// What a walkthrough needs from `PermissionsManager`. Tests substitute a fake.
@MainActor
protocol PermissionAuthority: AnyObject {
    /// What macOS last said about controlling each app, by bundle ID.
    var automationStatuses: [String: AutomationConsent.Status] { get }

    func isGranted(_ permission: Permission) -> Bool
    func refresh(_ permission: Permission)
    func refreshAutomation(for bundleIDs: [String])
    func request(_ permission: Permission) async
    @discardableResult
    func requestAutomation(for bundleIDs: [String]) async -> [String: AutomationConsent.Status]
    func openSettings(for permission: Permission)
}

extension PermissionsManager: PermissionAuthority {}

/// Asks for permissions one at a time: shows macOS's prompt for each, then waits for
/// the answer (or, for the ones granted in System Settings, for the switch to flip)
/// before going on to the next.
@MainActor
@Observable
final class PermissionWalkthrough {
    let plan: PermissionPlan
    /// The permission being asked for.
    private(set) var current: Permission?
    private(set) var skipped: Set<Permission> = []
    private(set) var isRunning = false
    /// Called when a permission granted in System Settings comes through, so the
    /// setup window can come back to the front.
    @ObservationIgnored var onGrantedInSettings: ((Permission) -> Void)?

    @ObservationIgnored private let authority: any PermissionAuthority
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var task: Task<Void, Never>?

    init(plan: PermissionPlan, authority: any PermissionAuthority, pollInterval: Duration = .milliseconds(500)) {
        self.plan = plan
        self.authority = authority
        self.pollInterval = pollInterval
    }

    /// Whether macOS answers `permission` in a dialog of its own, rather than with a
    /// switch in System Settings.
    static func isAnsweredInPlace(_ permission: Permission) -> Bool {
        permission == .automation || permission == .calendars
    }

    /// Automation goes by the plan's own apps (see `automationHoldouts`) rather than the
    /// manager's System Events stand-in.
    func isGranted(_ permission: Permission) -> Bool {
        permission == .automation ? automationHoldouts.isEmpty : authority.isGranted(permission)
    }

    /// The plan's apps macOS refused, or hasn't asked about yet. Apps that haven't run
    /// don't count, since they ask the first time Vibeshed scripts them; System Events
    /// does until it has answered, because it can be started just to ask.
    var automationHoldouts: [String] {
        plan.automationTargets.filter { bundleID in
            switch authority.automationStatuses[bundleID] {
            case .denied?, .notAsked?: true
            case .notRunning?, nil: bundleID == AutomationConsent.systemEvents
            case .allowed?: false
            }
        }
    }

    /// The plan's apps Vibeshed was refused control of. macOS won't ask again; only the
    /// Automation pane in System Settings changes it.
    var deniedAutomationTargets: [String] {
        plan.automationTargets.filter { authority.automationStatuses[$0] == .denied }
    }

    var allGranted: Bool {
        plan.permissions.allSatisfy(isGranted)
    }

    /// Asks for each of `permissions` that's missing, in order; the whole plan by default.
    func start(_ permissions: [Permission]? = nil) {
        guard !isRunning else { return }
        let steps = permissions ?? plan.permissions
        skipped.subtract(steps)
        isRunning = true
        task = Task { [weak self] in
            await self?.run(steps)
            self?.current = nil
            self?.isRunning = false
            self?.task = nil
        }
    }

    /// Moves on from the permission being waited on. A dialog macOS is showing can't
    /// be skipped; it has to be answered.
    func skip() {
        guard let current, !Self.isAnsweredInPlace(current) else { return }
        skipped.insert(current)
    }

    /// Stops once any dialog on screen is answered.
    func cancel() {
        task?.cancel()
    }

    func openSettings(for permission: Permission) {
        authority.openSettings(for: permission)
    }

    private func run(_ steps: [Permission]) async {
        for permission in steps where !isGranted(permission) {
            guard !Task.isCancelled else { return }
            current = permission
            if permission == .automation {
                await authority.requestAutomation(for: plan.automationTargets)
            } else {
                await authority.request(permission)
            }
            if !Self.isAnsweredInPlace(permission), await waitForGrant(of: permission) {
                onGrantedInSettings?(permission)
            }
        }
    }

    /// Polls until the permission is granted (true), or skipped or cancelled (false).
    private func waitForGrant(of permission: Permission) async -> Bool {
        while !Task.isCancelled, !skipped.contains(permission) {
            authority.refresh(permission)
            if authority.isGranted(permission) {
                return true
            }
            try? await Task.sleep(for: pollInterval)
        }
        return false
    }
}
