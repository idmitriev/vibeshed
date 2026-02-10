import AppKit
import QuartzCore
import SwiftUI

final class FloatingPanel: NSPanel {
    /// Called on Escape. Return `true` if handled (e.g. mode popped), `false` to close the panel.
    var onEscape: (() -> Bool)?

    /// Called before animated dismiss begins. Used so PanelController can update state.
    var onWillClose: (() -> Void)?

    /// Whether we're currently running a dismiss animation (prevents re-entrancy).
    private var isDismissing = false

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func resignKey() {
        super.resignKey()
        animateDismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape, onEscape() {
            return
        }
        animateDismiss()
    }

    func setSwiftUIContent(_ view: some View) {
        contentView = NSHostingView(rootView: view.ignoresSafeArea())
    }

    // MARK: - Show animation (called by PanelController)

    func animateShow() {
        isDismissing = false
        guard let layer = contentView?.layer else {
            alphaValue = 1
            return
        }

        // Ensure the content view is layer-backed
        contentView?.wantsLayer = true

        // Start state: scaled down, transparent, slightly lower
        alphaValue = 0
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        repositionLayerAnchor(layer)
        layer.transform = CATransform3DMakeScale(0.94, 0.94, 1)

        makeKeyAndOrderFront(nil)
        orderFrontRegardless()

        // Spring-style show animation
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
        )

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 0.94
        scaleAnim.toValue = 1.0
        scaleAnim.duration = 0.35
        scaleAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
        scaleAnim.isRemovedOnCompletion = false
        scaleAnim.fillMode = .forwards
        layer.add(scaleAnim, forKey: "showScale")

        CATransaction.commit()

        layer.transform = CATransform3DIdentity

        // Fade in with slightly faster timing
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }

    // MARK: - Dismiss animation

    func animateDismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        onWillClose?()

        guard let layer = contentView?.layer else {
            close()
            return
        }

        contentView?.wantsLayer = true
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        repositionLayerAnchor(layer)

        // Scale-down + fade-out dismiss
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
        )
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            self.close()
            // Reset for next show
            layer.transform = CATransform3DIdentity
            self.alphaValue = 0
            self.isDismissing = false
        }

        let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
        scaleAnim.fromValue = 1.0
        scaleAnim.toValue = 0.96
        scaleAnim.duration = 0.15
        scaleAnim.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
        scaleAnim.isRemovedOnCompletion = false
        scaleAnim.fillMode = .forwards
        layer.add(scaleAnim, forKey: "hideScale")

        CATransaction.commit()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
            self.animator().alphaValue = 0
        }
    }

    // MARK: - Helpers

    /// Reposition the layer's position after changing anchorPoint so the visual placement doesn't shift.
    private func repositionLayerAnchor(_ layer: CALayer) {
        let bounds = layer.bounds
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}
