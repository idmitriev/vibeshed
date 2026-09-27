import AppKit
import OSLog
import SwiftUI

@MainActor
@Observable
final class PanelController {
    private var panel: FloatingPanel?
    private let pickerState: PickerState
    private let configManager: ConfigManager
    var coordinator: PickerCoordinator?
    var themeEngine: ThemeEngine?
    @ObservationIgnored private nonisolated(unsafe) var windowCloseObserver: NSObjectProtocol?

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

    /// Backdrop behind the picker (`appearance.overlay`), shown and hidden with it.
    private let overlay = PickerOverlay()
    /// Invalidates older overlay-style observations when a new one starts.
    @ObservationIgnored private var overlayStyleWatch = 0

    init(pickerState: PickerState, configManager: ConfigManager) {
        self.pickerState = pickerState
        self.configManager = configManager
        // A click on the overlay is a click outside the picker: close it as losing focus
        // would (the next open starts fresh), and take the overlay down even if the
        // panel is somehow already gone.
        overlay.onClick = { [weak self] in
            self?.panel?.animateHide()
            self?.overlay.hide()
        }
    }

    deinit {
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// When true, the panel will not auto-hide on resignKey.
    /// Reset automatically when the panel hides.
    func setStaysOpenOnResignKey(_ value: Bool) {
        panel?.staysOpenOnResignKey = value
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

        // Start animation — heavy work fires in onShowAnimationDidComplete
        present(panel)
        isVisible = true
        Log.picker.debug("Panel shown")
    }

    func hide() {
        guard let panel, isVisible else { return }
        isHiddenWithState = true
        deferredLoad = nil
        panel.animateHide()
        isVisible = false
        coordinator?.syncLivePreview()
        Log.picker.debug("Panel hidden")
    }

    /// Re-shows the panel without resetting state. Used when an action's result
    /// needs the picker back (e.g. pushActions).
    func showRetainingState() {
        let panel = getOrCreatePanel()
        deferredLoad = nil
        present(panel)
        isVisible = true
        isHiddenWithState = false
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

    /// Fades the overlay out while a live preview (e.g. `theme/switch`) is changing the
    /// desktop behind it, and back in after.
    func setOverlaySuspended(_ suspended: Bool) {
        overlay.setSuspended(suspended)
    }

    /// Readies the overlay ahead of its first show, now and after every config change
    /// (see `PickerOverlay.prewarm`). Call once the config has loaded.
    func startOverlay() {
        let config = withObservationTracking {
            configManager.config.appearance.activeOverlay
        } onChange: { [weak self] in
            Task { @MainActor in self?.startOverlay() }
        }
        guard let config, let screen = NSScreen.main else { return }
        overlay.prewarm(config, style: overlayStyle(for: config), pickerScreen: screen)
    }

    // MARK: - Private

    /// Centres the panel on the active screen, puts the overlay behind it, and animates
    /// both in (layout is unavoidable sync work before the animation).
    private func present(_ panel: FloatingPanel) {
        let screen = NSScreen.main
        if let screen {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.midY - panel.frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        presentOverlay(behind: panel, on: screen)
        panel.animateShow()
    }

    private func presentOverlay(behind panel: FloatingPanel, on screen: NSScreen?) {
        guard let config = configManager.config.appearance.activeOverlay, let screen else {
            panel.level = .floating
            overlay.hide()
            return
        }
        // The overlay covers the menu bar and Dock, so the picker has to sit above it.
        panel.level = .pickerAboveOverlay
        overlay.show(config, style: overlayStyle(for: config), pickerFrame: panel.frame, on: screen)
        watchOverlayStyle()
    }

    private func overlayStyle(for config: AppConfig.OverlayConfig) -> OverlayStyle {
        let accent = themeEngine.flatMap { ThemeColor(nsColor: NSColor($0.theme.accent)) }
            ?? ThemeColor(nsColor: .controlAccentColor)
            ?? .black
        let tint = OverlayStyle.tint(
            for: config.color,
            palette: ActiveTheme.shared.displayed?.palette,
            accent: accent,
            isDarkAppearance: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        )
        return OverlayStyle(
            config: config,
            tint: tint,
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        )
    }

    /// Restyles the overlay while it's up when what it's drawn from changes: a theme
    /// applied or live-previewed, the dynamic accent, the config.
    private func watchOverlayStyle() {
        overlayStyleWatch += 1
        let watch = overlayStyleWatch
        withObservationTracking {
            _ = configManager.config.appearance.activeOverlay.map(overlayStyle(for:))
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.overlayStyleWatch == watch, self.overlay.isShown else { return }
                if let config = self.configManager.config.appearance.activeOverlay {
                    self.overlay.restyle(self.overlayStyle(for: config))
                }
                self.watchOverlayStyle()
            }
        }
    }

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

        let appearance = configManager.config.appearance
        // Outer 16pt padding on each side accommodates the panel shadow.
        let frame = NSRect(
            x: 0,
            y: 0,
            width: appearance.panelWidth + 32,
            height: appearance.panelHeight + 32
        )
        let newPanel = FloatingPanel(contentRect: frame)

        newPanel.onEscape = { [weak self] in
            guard let self else { return false }
            return self.pickerState.popMode()
        }

        newPanel.onWillHide = { [weak self] in
            MainActor.assumeIsolated {
                // Every way the panel hides (Escape, focus loss, an action) passes here.
                self?.overlay.hide()
                self?.isVisible = false
                self?.coordinator?.syncLivePreview()
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
                    appearance: appearance,
                    themeEngine: engine
                )
            )
        } else {
            newPanel.setSwiftUIContent(
                PickerView(state: pickerState, panelController: self, appearance: appearance)
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
    let appearance: AppConfig.AppearanceConfig
    let themeEngine: ThemeEngine

    var body: some View {
        PickerView(state: state, panelController: panelController, appearance: appearance)
            .environment(\.vibeTheme, themeEngine.theme)
    }
}
