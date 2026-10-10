import AppKit

/// The backdrop behind the open picker (`appearance.overlay`): one `OverlayWindow` per
/// covered screen, shown and hidden in step with the panel by `PanelController`.
@MainActor
final class PickerOverlay {
    /// Called when the overlay itself is clicked; closes the picker.
    var onClick: (() -> Void)?

    private(set) var isShown = false
    private var isSuspended = false
    private var config = AppConfig.OverlayConfig()
    /// Created on demand and reused; `active` are the ones covering this session's screens.
    private var windows: [OverlayWindow] = []
    private var active: [OverlayWindow] = []
    /// Bumped by every show, so a prewarm doesn't order out a window that's been shown since.
    private var showGeneration = 0

    private static let suspendDuration: TimeInterval = 0.25

    func show(_ config: AppConfig.OverlayConfig, style: OverlayStyle, pickerFrame: NSRect, on pickerScreen: NSScreen) {
        let wasShown = isShown
        let wasSuspended = isSuspended
        self.config = config
        isShown = true
        isSuspended = false
        showGeneration += 1

        let screens = config.allScreens ? NSScreen.screens : [pickerScreen]
        active = Array(ensureWindows(screens.count))
        for window in windows.dropFirst(screens.count) where window.isVisible {
            window.orderOut(nil)
        }

        let animation = Self.effectiveAnimation(config.showAnimation)
        for (window, screen) in zip(active, screens) {
            let wasVisible = window.isVisible
            if !wasVisible {
                window.overlayView.prepareForShow()
            }
            place(window, on: screen, style: style, picker: screen.frame == pickerScreen.frame ? pickerFrame : nil)
            window.ignoresMouseEvents = config.clickThrough
            window.orderFrontRegardless()
            if !wasShown || !wasVisible {
                window.overlayView.animateIn(animation, duration: config.showDuration)
            } else if wasSuspended {
                window.overlayView.fade(to: 1, duration: Self.suspendDuration)
            }
        }
        if !wasShown {
            let message = "Overlay shown on \(screens.count) screen(s): \(animation.rawValue), \(config.showDuration)s"
            Log.picker.debug("\(message, privacy: .public)")
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        isSuspended = false
        let animation = Self.effectiveAnimation(config.hideAnimation)
        for window in active where window.isVisible {
            // Clicks go through to whatever is underneath while it fades.
            window.ignoresMouseEvents = true
            window.overlayView.animateOut(animation, duration: config.hideDuration) { [weak window] in
                window?.orderOut(nil)
                Log.picker.debug("Overlay hidden")
            }
        }
    }

    /// Fades the overlay out while something behind it needs to be seen — a live preview
    /// changing the desktop — and back in after.
    func setSuspended(_ suspended: Bool) {
        guard isShown, suspended != isSuspended else { return }
        isSuspended = suspended
        Log.picker.debug("Overlay \(suspended ? "suspended" : "resumed", privacy: .public) for a live preview")
        for window in active {
            window.overlayView.fade(to: suspended ? 0 : 1, duration: Self.suspendDuration)
        }
    }

    /// Picks up a new theme color or config while the overlay is up.
    func restyle(_ style: OverlayStyle) {
        guard isShown else { return }
        for window in active {
            window.overlayView.restyle(style)
        }
    }

    /// Gets windows ready ahead of a show. AppKit only builds a window's blur on its first
    /// display pass, which on the first show after launch lands ~150ms into the animation
    /// and pops the blur in late — so cold windows are ordered in for a moment first,
    /// invisible and click-through.
    func prewarm(_ config: AppConfig.OverlayConfig, style: OverlayStyle, pickerScreen: NSScreen) {
        guard !isShown else { return }
        let screens = config.allScreens ? NSScreen.screens : [pickerScreen]
        let cold = zip(ensureWindows(screens.count), screens).filter { window, _ in
            !window.isVisible && !window.overlayView.isWarm
        }
        guard !cold.isEmpty else { return }
        for (window, screen) in cold {
            window.overlayView.prepareForShow()
            place(window, on: screen, style: style, picker: nil)
            window.ignoresMouseEvents = true
            window.orderFrontRegardless()
        }
        let generation = showGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.showGeneration == generation else { return }
            for (window, _) in cold {
                window.orderOut(nil)
            }
        }
    }

    // MARK: - Private

    /// The first `count` windows, creating any that don't exist yet.
    private func ensureWindows(_ count: Int) -> ArraySlice<OverlayWindow> {
        while windows.count < count {
            let window = OverlayWindow()
            window.onClick = { [weak self] in self?.onClick?() }
            windows.append(window)
        }
        return windows.prefix(count)
    }

    /// Sizes `window` to `screen` and styles it around the picker (`picker`, when it's on
    /// this screen) or the screen's centre.
    private func place(_ window: OverlayWindow, on screen: NSScreen, style: OverlayStyle, picker: NSRect?) {
        window.setFrame(screen.frame, display: false)
        let center = CGPoint(x: (picker ?? screen.frame).midX, y: (picker ?? screen.frame).midY)
        window.overlayView.apply(
            style,
            focus: CGPoint(x: center.x - screen.frame.minX, y: center.y - screen.frame.minY),
            focusRadius: picker.map { min($0.width, $0.height) / 2 } ?? 0
        )
    }

    /// Reduce Motion swaps the moving animations for a cross-fade.
    private static func effectiveAnimation(_ animation: OverlayAnimation) -> OverlayAnimation {
        guard NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, animation != .none else { return animation }
        return .fade
    }
}

/// Borderless, non-activating, screen-sized window drawn under the picker. It never
/// becomes key, so the picker keeps keyboard focus; a click on it closes the picker
/// without reaching (or activating) the app underneath.
final class OverlayWindow: NSPanel {
    let overlayView = OverlayContentView(frame: .zero)
    var onClick: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .pickerOverlay
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        contentView = overlayView
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Keep the full screen frame: AppKit would otherwise pull it below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            onClick?()
        default:
            super.sendEvent(event)
        }
    }
}
