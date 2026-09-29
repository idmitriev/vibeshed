/// The permissions to ask for, and in what order, for what the config loads.
struct PermissionPlan: Equatable, Sendable {
    /// Accessibility first: without it there's no picker hotkey. Then the dialogs macOS
    /// answers in place, then the two after which macOS may offer to quit and reopen
    /// Vibeshed, so that restart comes at the end rather than midway.
    static let order: [Permission] = [
        .accessibility, .automation, .calendars, .fullDiskAccess, .inputMonitoring, .screenRecording,
    ]

    let permissions: [Permission]
    /// Apps to ask about for Automation: System Events first, the rest by bundle ID
    /// (so Apple's apps come next).
    let automationTargets: [String]

    init(
        required: Set<Permission>,
        optional: Set<Permission> = [],
        automationTargets: Set<String> = [],
        usesCapsLock: Bool = false
    ) {
        var wanted = required.union(optional)
        wanted.insert(.accessibility)
        if usesCapsLock {
            wanted.insert(.inputMonitoring)
        }
        if !automationTargets.isEmpty {
            wanted.insert(.automation)
        }
        permissions = Self.order.filter(wanted.contains)
        self.automationTargets = automationTargets.sorted { lhs, rhs in
            let lhsFirst = lhs == AutomationConsent.systemEvents
            let rhsFirst = rhs == AutomationConsent.systemEvents
            return lhsFirst == rhsFirst ? lhs.lowercased() < rhs.lowercased() : lhsFirst
        }
    }
}
