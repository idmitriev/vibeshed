import SwiftUI

@main
struct VibeshedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Vibeshed", systemImage: "sparkle") {
            StatusBarView(panelController: appDelegate.panelController)
        }

        Settings {
            Text("Settings placeholder")
                .frame(width: 400, height: 300)
        }
    }
}
