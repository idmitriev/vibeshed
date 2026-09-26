import AppKit
import SwiftUI

/// Shows recent keystrokes in a click-through overlay at the bottom of the
/// screen under the mouse, marking the ones a Vibeshed keybinding or remap
/// handled. Keystrokes come from `KeyComboManager`'s event tap.
@MainActor
@Observable
final class KeystrokeVisualizer {
    private(set) var isEnabled = false
    private(set) var log = KeystrokeLog()

    @ObservationIgnored private let keyComboManager: KeyComboManager
    @ObservationIgnored private let themeEngine: ThemeEngine
    @ObservationIgnored private let resolveActionTitle: @MainActor (ActionID) async -> String?
    @ObservationIgnored private var panel: KeystrokeOverlayPanel?
    @ObservationIgnored private var actionTitles: [ActionID: String] = [:]

    init(
        keyComboManager: KeyComboManager,
        themeEngine: ThemeEngine,
        resolveActionTitle: @escaping @MainActor (ActionID) async -> String?
    ) {
        self.keyComboManager = keyComboManager
        self.themeEngine = themeEngine
        self.resolveActionTitle = resolveActionTitle
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        log.removeAll()
        if enabled {
            // Main-queue hops keep keystrokes in the order they were typed.
            keyComboManager.setKeystrokeSink { [weak self] keystroke in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.record(keystroke) }
                }
            }
            showPanel()
        } else {
            keyComboManager.setKeystrokeSink(nil)
            panel?.orderOut(nil)
            actionTitles.removeAll()
        }
        Log.keybindings.info("Keystroke visualizer \(enabled ? "on" : "off", privacy: .public)")
    }

    // MARK: - Recording

    private func record(_ keystroke: KeystrokeEvent) {
        guard isEnabled else { return }
        if log.chips.isEmpty {
            placePanel() // Follow the mouse between bursts, not mid-burst.
        }
        let now = Date()
        let chip = log.record(keystroke, at: now)
        if case let .binding(actionID) = chip.kind {
            captionBinding(actionID)
        }
        let lifetime: Duration = chip.isVibeshed ? .seconds(3) : .seconds(2)
        Task { [weak self] in
            try? await Task.sleep(for: lifetime)
            self?.log.expire(chip.id, ifUnchangedSince: now)
        }
    }

    private func captionBinding(_ actionID: ActionID) {
        if let title = actionTitles[actionID] {
            log.setCaption(title, for: actionID)
            return
        }
        Task { [weak self] in
            guard let self, let title = await resolveActionTitle(actionID) else { return }
            actionTitles[actionID] = title
            log.setCaption(title, for: actionID)
        }
    }

    // MARK: - Panel

    private func showPanel() {
        let overlay = panel ?? makePanel()
        panel = overlay
        placePanel()
        overlay.orderFrontRegardless()
    }

    private func makePanel() -> KeystrokeOverlayPanel {
        let overlay = KeystrokeOverlayPanel()
        let hostingView = NSHostingView(
            rootView: KeystrokeOverlayView(visualizer: self, themeEngine: themeEngine)
        )
        // The panel is sized to the screen, not to the chips.
        hostingView.sizingOptions = []
        overlay.contentView = hostingView
        return overlay
    }

    /// Bottom-centre of the screen under the mouse.
    private func placePanel() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
        else {
            return
        }
        let area = screen.visibleFrame
        let width = min(960, area.width - 32)
        let height: CGFloat = 420
        let frame = NSRect(x: area.midX - width / 2, y: area.minY + 48, width: width, height: height)
        panel.setFrame(frame, display: false)
    }
}

/// Borderless, click-through, above everything, on every Space.
private final class KeystrokeOverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
