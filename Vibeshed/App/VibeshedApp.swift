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
            Image(nsImage: MenuBarIcon.make())
        }
    }
}
