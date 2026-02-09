import SwiftUI

struct StatusBarView: View {
    let panelController: PanelController

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

        SettingsLink {
            Text("Preferences...")
        }

        Divider()

        Button("Quit Vibeshed") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
