import AppKit
import QuartzCore

/// Transparent, click-through, always-on-top panel that draws the focus border. The ring
/// is a plain `CALayer` border, so moving and restyling it happens in the same transaction
/// as the window frame change — no view layout pass in between. Never becomes key/main so
/// it can't steal focus.
final class FocusBorderPanel: NSPanel {
    private let borderLayer = CALayer()

    init() {
        super.init(
            contentRect: .zero,
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
        animationBehavior = .none

        let content = NSView()
        content.layer = CALayer()
        content.wantsLayer = true
        borderLayer.cornerCurve = .continuous
        content.layer?.addSublayer(borderLayer)
        contentView = content
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    /// Surrounds `cgFrame` (a window frame, CG top-left-origin). The panel is the frame
    /// outset by `width` on every side and the layer draws its border inside the panel's
    /// edge, so the ring sits entirely outside the window: its inner edge on the window's
    /// edge, nothing drawn over the window's content. `cornerRadius` is the window's own;
    /// a layer border's inner corners are its outer radius minus the width, so the outer
    /// radius is grown by `width` to keep the inner edge on the window's rounded corner.
    func surround(_ cgFrame: CGRect, width: Double, cornerRadius: Double, color: CGColor) {
        let frame = WindowSizing.appKitFrame(fromCG: cgFrame.insetBy(dx: -width, dy: -width))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.frame != frame {
            setFrame(frame, display: false)
        }
        borderLayer.frame = CGRect(origin: .zero, size: frame.size)
        borderLayer.borderWidth = width
        borderLayer.cornerRadius = cornerRadius > 0 ? cornerRadius + width : 0
        borderLayer.borderColor = color
        CATransaction.commit()
    }
}
