import AppKit
import OSLog
import SwiftUI

@MainActor
@Observable
final class PanelController {
    private var panel: FloatingPanel?
    private let pickerState: PickerState
    var coordinator: PickerCoordinator?
    var themeEngine: ThemeEngine?

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

        if let shadowColor = themeEngine?.theme.shadowColor {
            panel.contentView?.wantsLayer = true
            panel.contentView?.layer?.shadowColor = NSColor(shadowColor).cgColor
            panel.contentView?.layer?.shadowOpacity = 1
            panel.contentView?.layer?.shadowRadius = 20
            panel.contentView?.layer?.shadowOffset = .zero
        } else {
            panel.contentView?.layer?.shadowOpacity = 0
        }

        panel.animateShow()
        isVisible = true
        Log.picker.debug("Panel shown")
    }

    func hide() {
        guard let panel, isVisible else { return }
        panel.animateDismiss()
        Log.picker.debug("Panel hidden")
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

        if let engine = themeEngine {
            newPanel.setSwiftUIContent(
                ThemedPickerWrapper(
                    state: pickerState,
                    panelController: self,
                    themeEngine: engine
                )
            )
        } else {
            newPanel.setSwiftUIContent(
                PickerView(state: pickerState, panelController: self)
            )
        }

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

// MARK: - Themed Wrapper

/// Observes ThemeEngine and injects VibeTheme into the SwiftUI environment.
/// Needed because NSHostingView content is set once, but @Observable
/// dependency on themeEngine triggers re-renders when theme changes.
private struct ThemedPickerWrapper: View {
    @Bindable var state: PickerState
    let panelController: PanelController
    let themeEngine: ThemeEngine

    var body: some View {
        PickerView(state: state, panelController: panelController)
            .environment(\.vibeTheme, themeEngine.theme)
    }
}
