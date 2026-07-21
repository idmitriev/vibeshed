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

extension Color {
    /// Parses a "#RRGGBB" or "RRGGBB" hex string. Returns nil if malformed (used both to
    /// render the border and to validate `FocusBorderConfig.color` in `TilingModule.validate`).
    init?(tilingHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let intValue = UInt64(cleaned, radix: 16) else { return nil }
        let red = Double((intValue >> 16) & 0xFF) / 255.0
        let green = Double((intValue >> 8) & 0xFF) / 255.0
        let blue = Double(intValue & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
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
    func show(cgFrame: CGRect, colorHex: String, width: Double, cornerRadius: Double) {
        let color = Color(tilingHex: colorHex) ?? .accentColor
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
