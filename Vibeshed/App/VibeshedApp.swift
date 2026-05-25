import SwiftUI

@main
struct VibeshedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusBarView(
                panelController: appDelegate.panelController,
                permissionsManager: appDelegate.permissionsManager,
                moduleRegistry: appDelegate.moduleRegistry,
                autostartManager: appDelegate.autostartManager
            )
        } label: {
            MenuBarLabel()
        }
    }
}

private struct MenuBarLabel: View {
    @State private var capsLockActive = CapsLockMonitor.shared.isPressed

    var body: some View {
        Image(nsImage: MenuBarIcon.make(capsLockActive: capsLockActive))
            .onReceive(
                NotificationCenter.default.publisher(for: CapsLockMonitor.stateChanged)
            ) { _ in
                capsLockActive = CapsLockMonitor.shared.isPressed
            }
    }
}
