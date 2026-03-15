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
    @ObservationIgnored nonisolated(unsafe) private var windowCloseObserver: NSObjectProtocol?

    private(set) var isVisible: Bool = false

    /// Tracks whether panel was hidden (orderOut) vs never created.
    /// When true, state is retained and we can skip reset on next show.
    private var isHiddenWithState: Bool = false

    /// What kind of load to perform after the show animation completes.
    private enum DeferredLoad {
        case initial
        case refresh
    }

    private var deferredLoad: DeferredLoad?

    init(pickerState: PickerState) {
        self.pickerState = pickerState
    }

    deinit {
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = getOrCreatePanel()

        // Determine load strategy but defer actual heavy work until animation finishes
        if isHiddenWithState {
            deferredLoad = .refresh
        } else {
            pickerState.reset()
            coordinator?.clearContext()
            // Show cached results synchronously (fast — just array copy, no async)
            coordinator?.showCachedActionsIfAvailable()
            deferredLoad = .initial
        }
        isHiddenWithState = false

        // Layout + shadow before animation (unavoidable sync work)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.maxY - panel.frame.height - screenFrame.height * 0.2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Start animation — heavy work fires in onShowAnimationDidComplete
        panel.animateShow()
        isVisible = true
        Log.picker.debug("Panel shown")
    }

    func hide() {
        guard let panel, isVisible else { return }
        isHiddenWithState = true
        deferredLoad = nil
        panel.animateHide()
        isVisible = false
        Log.picker.debug("Panel hidden")
    }

    /// Called after action execution — resets state so next show is fresh.
    func hideAndReset() {
        guard let panel, isVisible else { return }
        isHiddenWithState = false
        deferredLoad = nil
        pickerState.reset()
        coordinator?.clearContext()
        panel.animateHide()
        isVisible = false
        Log.picker.debug("Panel hidden (state reset)")
    }

    // MARK: - Private

    private func onShowAnimationDidComplete() {
        guard let load = deferredLoad else { return }
        deferredLoad = nil

        switch load {
        case .initial:
            coordinator?.loadInitialActions()
        case .refresh:
            coordinator?.refreshInPlace()
        }
    }

    private func getOrCreatePanel() -> FloatingPanel {
        if let existing = panel { return existing }

        // 680×460 content + 16pt padding on each side for shadow
        let frame = NSRect(x: 0, y: 0, width: 712, height: 492)
        let newPanel = FloatingPanel(contentRect: frame)

        newPanel.onEscape = { [weak self] in
            guard let self else { return false }
            return self.pickerState.popMode()
        }

        newPanel.onWillHide = { [weak self] in
            MainActor.assumeIsolated {
                self?.isVisible = false
            }
        }

        newPanel.onShowAnimationComplete = { [weak self] in
            MainActor.assumeIsolated {
                self?.onShowAnimationDidComplete()
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

        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newPanel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isVisible = false
                self?.isHiddenWithState = false
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
