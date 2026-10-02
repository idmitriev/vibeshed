import SwiftUI

/// Permission setup: a greeting on first launch, a row per permission with where it
/// stands, and one button that asks for all of them in turn.
struct PermissionSetupView: View {
    struct Context {
        /// First launch: greet, and name the apps the new config was set up for.
        var isWelcome: Bool
        var hotkey: String?
        var software: [String]
        /// The installed apps the Automation step asks about, by name.
        var automationApps: [String]
    }

    let walkthrough: PermissionWalkthrough
    let context: Context
    let openConfig: () -> Void
    let done: () -> Void

    private static let permissionsIntro =
        "macOS asks for each one separately. Grant them now and every module works the first time you use it."

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if context.isWelcome, !context.software.isEmpty {
                softwareSection
            }
            permissionsSection
            footer
        }
        .padding(24)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(context.isWelcome ? "Welcome to Vibeshed" : "Vibeshed Permissions")
                    .font(.title2.weight(.semibold))
                if let hotkey = context.hotkey {
                    Text("Press \(Text(hotkey).fontWeight(.semibold)) in any app to open the picker.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var softwareSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set up for the apps on this Mac")
                .font(.headline)
            Text(softwareList)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Edit config.yaml", action: openConfig)
                .buttonStyle(.link)
        }
    }

    /// Non-breaking spaces keep a name like "VS Code" on one line.
    private var softwareList: String {
        let names = context.software.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }
        return ListFormatter.localizedString(byJoining: names)
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if context.isWelcome {
                Text("Permissions")
                    .font(.headline)
            }
            Text(Self.permissionsIntro)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(walkthrough.plan.permissions, id: \.self) { permission in
                    if permission != walkthrough.plan.permissions.first {
                        Divider()
                    }
                    PermissionRow(
                        walkthrough: walkthrough,
                        permission: permission,
                        automationApps: context.automationApps
                    )
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
        }
    }

    private var footer: some View {
        HStack {
            if walkthrough.allGranted {
                Text("You're all set.")
                    .foregroundStyle(.secondary)
            } else {
                Button("Later", action: done)
            }
            Spacer()
            if walkthrough.allGranted {
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(walkthrough.isRunning ? "Granting…" : "Grant Permissions") {
                    walkthrough.start()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(walkthrough.isRunning)
            }
        }
    }
}

private struct PermissionRow: View {
    let walkthrough: PermissionWalkthrough
    let permission: Permission
    let automationApps: [String]

    private var isCurrent: Bool {
        walkthrough.current == permission
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: permission.symbolName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName)
                Text(isCurrent ? hint : purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isCurrent, !PermissionWalkthrough.isAnsweredInPlace(permission) {
                    HStack(spacing: 8) {
                        Button("Open System Settings") { walkthrough.openSettings(for: permission) }
                        Button("Skip") { walkthrough.skip() }
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            status
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var status: some View {
        if walkthrough.isGranted(permission) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
        } else if isCurrent {
            ProgressView()
                .controlSize(.small)
        } else {
            Button(walkthrough.skipped.contains(permission) ? "Try Again" : "Grant") {
                walkthrough.start([permission])
            }
            .disabled(walkthrough.isRunning)
        }
    }

    /// What the permission is for.
    private var purpose: String {
        switch permission {
        case .accessibility:
            "Keyboard shortcuts, moving and resizing windows, and pasting into apps."
        case .automation where !automationApps.isEmpty:
            "Controlling \(ListFormatter.localizedString(byJoining: automationApps)). "
                + "Apps that aren't open ask the first time Vibeshed uses them."
        case .automation:
            "Controlling other apps."
        case .calendars:
            "Upcoming events and their meeting links."
        case .fullDiskAccess:
            "Safari bookmarks and history."
        case .inputMonitoring:
            "Caps Lock as a modifier key, which your shortcuts use."
        case .screenRecording:
            "Window titles, for finding and switching windows."
        }
    }

    /// What to do while it's being asked for.
    private var hint: String {
        switch permission {
        case .accessibility:
            "Turn on Vibeshed in System Settings, then come back here."
        case .inputMonitoring, .screenRecording:
            "Turn on Vibeshed in System Settings. If macOS offers to quit and reopen it, go ahead: "
                + "setup picks up where it left off."
        case .fullDiskAccess:
            "In System Settings, click + and add Vibeshed from Applications."
        case .automation:
            "Click Allow each time macOS asks about an app."
        case .calendars:
            "Allow access when macOS asks."
        }
    }
}

private extension Permission {
    var symbolName: String {
        switch self {
        case .accessibility: "accessibility"
        case .automation: "gearshape.2"
        case .calendars: "calendar"
        case .fullDiskAccess: "internaldrive"
        case .inputMonitoring: "keyboard"
        case .screenRecording: "rectangle.dashed.badge.record"
        }
    }
}
