import AppKit
import SwiftUI

/// Transparent, click-through, always-on-top panel used to draw a border around the
/// currently focused tiled window. Never becomes key/main so it can't steal focus.
final class FocusBorderPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        contentView?.wantsLayer = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setSwiftUIContent(_ view: some View) {
        contentView = NSHostingView(rootView: view.ignoresSafeArea())
        contentView?.wantsLayer = true
    }
}

private struct FocusBorderShape: View {
    let color: Color
    let width: Double
    let cornerRadius: Double

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(color, lineWidth: width)
    }
}

/// Owns the single shared `FocusBorderPanel` instance. `@MainActor` singleton (mirrors
/// `WebAuthContextProvider` in the Spotify module) so actor-isolated `TilingModule` can
/// drive AppKit window state via `await FocusBorderController.shared.show(...)`.
@MainActor
final class FocusBorderController {
    static let shared = FocusBorderController()

    private var panel: FocusBorderPanel?

    private init() {}

    /// Shows (or moves) the border to surround `cgFrame` — the panel is outset by `width` on
    /// every side so the stroke sits entirely outside the target window, not overlapping it.
    /// Drawn in the active theme's accent, re-read on every show so theme switches (and
    /// live previews) retint the border immediately.
    func show(cgFrame: CGRect, width: Double, cornerRadius: Double) {
        let color = ActiveTheme.shared.displayed?.palette.accent.color ?? Color(nsColor: .controlAccentColor)
        let outsetFrame = cgFrame.insetBy(dx: -width, dy: -width)
        let panel = getOrCreatePanel()
        panel.setSwiftUIContent(FocusBorderShape(color: color, width: width, cornerRadius: cornerRadius))
        panel.setFrame(WindowSizing.appKitFrame(fromCG: outsetFrame), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func getOrCreatePanel() -> FocusBorderPanel {
        if let existing = panel { return existing }
        let newPanel = FocusBorderPanel(contentRect: .zero)
        panel = newPanel
        return newPanel
    }
}
