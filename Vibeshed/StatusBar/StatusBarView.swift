import SwiftUI

struct StatusBarView: View {
    let panelController: PanelController
    let permissionsManager: PermissionsManager
    let moduleRegistry: ModuleRegistry
    let autostartManager: AutostartManager

    private var missingPermissions: [Permission] {
        moduleRegistry.requiredPermissions
            .filter { !permissionsManager.isGranted($0) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        Button {
            panelController.toggle()
        } label: {
            if panelController.isVisible {
                Text("Hide Picker")
            } else {
                Text("Show Picker")
            }
        }
        .keyboardShortcut("p", modifiers: [.command])

        Divider()

        permissionsSection

        Divider()

        Toggle(
            "Launch at Login",
            isOn: Binding(
                get: { autostartManager.isEnabled },
                set: { _ in autostartManager.toggle() }
            )
        )

        Divider()

        Button("Quit Vibeshed") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var permissionsSection: some View {
        let missing = missingPermissions
        if missing.isEmpty {
            Label("All Permissions Granted", systemImage: "checkmark.circle.fill")
        } else {
            Menu {
                ForEach(missing, id: \.self) { permission in
                    Button {
                        if let url = permission.systemSettingsURL {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(permission.displayName, systemImage: "xmark.circle")
                    }
                }
            } label: {
                let count = missing.count
                Label(
                    "\(count) Missing Permission\(count == 1 ? "" : "s")",
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
        }
    }
}
