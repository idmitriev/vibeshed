import AppKit
import SwiftUI

@MainActor
@Observable
final class PanelController {
    private var panel: FloatingPanel?
    private let pickerState: PickerState

    private(set) var isVisible: Bool = false

    init(pickerState: PickerState) {
        self.pickerState = pickerState
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = getOrCreatePanel()
        pickerState.reset()

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.maxY - panel.frame.height - screenFrame.height * 0.2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.close()
        isVisible = false
    }

    private func getOrCreatePanel() -> FloatingPanel {
        if let existing = panel { return existing }

        let frame = NSRect(x: 0, y: 0, width: 680, height: 460)
        let newPanel = FloatingPanel(contentRect: frame)

        newPanel.setSwiftUIContent(
            PickerView(state: pickerState, panelController: self)
        )

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isVisible = false
            }
        }

        self.panel = newPanel
        return newPanel
    }
}
