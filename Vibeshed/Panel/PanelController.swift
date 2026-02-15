import AppKit
import SwiftUI

@MainActor
@Observable
final class PanelController {
    private var panel: FloatingPanel?
    private let pickerState: PickerState
    var coordinator: PickerCoordinator?

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
        coordinator?.clearContext()

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.maxY - panel.frame.height - screenFrame.height * 0.2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.animateShow()
        isVisible = true
    }

    func hide() {
        guard let panel, isVisible else { return }
        panel.animateDismiss()
        // isVisible is set to false by the onWillClose callback
    }

    private func getOrCreatePanel() -> FloatingPanel {
        if let existing = panel { return existing }

        let frame = NSRect(x: 0, y: 0, width: 680, height: 460)
        let newPanel = FloatingPanel(contentRect: frame)

        newPanel.onEscape = { [weak self] in
            guard let self else { return false }
            return self.pickerState.popMode()
        }

        newPanel.onWillClose = { [weak self] in
            MainActor.assumeIsolated {
                self?.isVisible = false
            }
        }

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

        panel = newPanel
        return newPanel
    }
}
