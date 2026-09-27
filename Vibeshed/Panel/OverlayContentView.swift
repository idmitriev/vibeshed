import AppKit
import QuartzCore

/// One screen's overlay: the tuned system blur with tint, vignette and grain layers on
/// top, animated in and out as a whole through its layer's opacity (and, for the iris,
/// a mask).
final class OverlayContentView: NSView {
    private let blurView = BackdropBlurView(frame: .zero)
    /// Layer-hosting, so the effect layers below are ours to manage.
    private let effectsView = NSView(frame: .zero)
    private let tintLayer = CALayer()
    private let vignetteLayer = CAGradientLayer()
    private let grainTile = CALayer()
    private let grainRow = CAReplicatorLayer()
    private let grainGrid = CAReplicatorLayer()

    private var style: OverlayStyle?
    /// The picker's centre in this view, and about half its size: where the vignette
    /// centres and the iris opens from.
    private var focus = CGPoint.zero
    private var focusRadius: CGFloat = 0
    /// Bumped by every transition so a superseded one's completion does nothing.
    private var transition = 0

    private static let opacityKey = "overlay.opacity"
    private static let irisKey = "overlay.iris"
    /// Share of the iris circle that's fully opaque; the rest is its soft edge.
    private static let irisCore: CGFloat = 0.8
    private static let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    private static let easeIn = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.opacity = 0

        blurView.frame = bounds
        blurView.autoresizingMask = [.width, .height]
        addSubview(blurView)

        effectsView.layer = CALayer()
        effectsView.wantsLayer = true
        effectsView.frame = bounds
        effectsView.autoresizingMask = [.width, .height]
        addSubview(effectsView)

        vignetteLayer.type = .radial
        vignetteLayer.locations = [0, 0.35, 0.65, 0.85, 1]
        // A faint ramp across a whole screen bands visibly at 8 bits per channel.
        vignetteLayer.contentsFormat = .RGBA16Float
        grainTile.magnificationFilter = .nearest
        grainRow.addSublayer(grainTile)
        grainGrid.addSublayer(grainRow)
        for sublayer in [tintLayer, vignetteLayer, grainGrid] {
            effectsView.layer?.addSublayer(sublayer)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Whether the blur is built, or not needed: a window that has never been on screen
    /// has no blur until its first display pass.
    var isWarm: Bool {
        !(style?.usesBackdrop ?? true) || blurView.hasBackdrop
    }

    // MARK: - Style

    /// Lays the overlay out for a new session: its style and where the picker sits.
    func apply(_ style: OverlayStyle, focus: CGPoint, focusRadius: CGFloat) {
        self.focus = focus
        self.focusRadius = focusRadius
        self.style = nil
        restyle(style)
    }

    /// Switches style in place; colors cross-fade if the overlay is already up.
    func restyle(_ style: OverlayStyle) {
        let isFirstApply = self.style == nil
        self.style = style

        blurView.isHidden = !style.usesBackdrop
        if style.usesBackdrop {
            // Setting a material rebuilds the backdrop, dropping a blur ramp in flight.
            let material = style.material.visualEffectMaterial
            if blurView.material != material {
                blurView.material = material
            }
            blurView.tuning = BackdropBlurView.Tuning(
                radius: style.blur,
                saturation: style.saturation,
                showsMaterialTint: style.material != .none
            )
        }

        let size = effectsView.bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(isFirstApply)
        tintLayer.backgroundColor = style.tint.cgColor(alpha: style.opacity)
        vignetteLayer.colors = [0, 0, 0.3, 0.7, 1].map { style.tint.cgColor(alpha: $0 * style.vignette) }
        vignetteLayer.isHidden = style.vignette == 0
        grainGrid.opacity = Float(style.grain)
        grainGrid.isHidden = style.grain == 0
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = CGRect(origin: .zero, size: size)
        vignetteLayer.frame = CGRect(origin: .zero, size: size)
        vignetteLayer.contentsScale = window?.backingScaleFactor ?? 2
        let radius = OverlayGeometry.coverRadius(from: focus, in: size)
        let points = OverlayGeometry.radialPoints(focus: focus, radius: radius, in: size)
        vignetteLayer.startPoint = points.start
        vignetteLayer.endPoint = points.end
        if style.grain > 0 {
            layoutGrain(in: size)
        }
        CATransaction.commit()
    }

    /// Repeats the grain tile across the view with two nested replicators.
    private func layoutGrain(in size: CGSize) {
        guard let tile = OverlayGrain.tile else { return }
        let side = CGFloat(OverlayGrain.tileSize)
        grainTile.contents = tile
        grainTile.frame = CGRect(x: 0, y: 0, width: side, height: side)
        grainRow.frame = CGRect(x: 0, y: 0, width: size.width, height: side)
        grainRow.instanceCount = max(1, Int((size.width / side).rounded(.up)))
        grainRow.instanceTransform = CATransform3DMakeTranslation(side, 0, 0)
        grainGrid.frame = CGRect(origin: .zero, size: size)
        grainGrid.instanceCount = max(1, Int((size.height / side).rounded(.up)))
        grainGrid.instanceTransform = CATransform3DMakeTranslation(0, side, 0)
    }
}

// MARK: - Transitions

extension OverlayContentView {
    /// Starts a window that's off screen from fully transparent.
    func prepareForShow() {
        beginTransition()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = 0
        CATransaction.commit()
    }

    /// Brings the overlay in. From part-way (a hide cut short) it just fades back up.
    func animateIn(_ animation: OverlayAnimation, duration: TimeInterval) {
        guard let layer else { return }
        let from = presentedOpacity
        let kind = effectiveKind(animation, duration: duration, resuming: from > 0.01)
        let token = beginTransition()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            // The iris mask is only needed while it opens; masking a full-screen blur
            // for the whole session would cost an offscreen pass every frame.
            guard let self, self.transition == token else { return }
            self.layer?.mask = nil
        }
        layer.opacity = 1
        switch kind {
        case .none:
            break
        case .fade:
            addOpacity(from: from, to: 1, duration: duration * Double(1 - from), timing: Self.easeOut)
        case .blur:
            addOpacity(from: 0, to: 1, duration: duration * 0.6, timing: Self.easeOut)
            blurView.rampRadius(from: 0, to: style?.blur ?? 0, duration: duration, timing: Self.easeOut)
        case .iris:
            addIris(from: irisClosedScale, to: 1, duration: duration, timing: Self.easeOut)
            addOpacity(from: 0, to: 1, duration: duration * 0.35, timing: Self.easeOut)
        }
        CATransaction.commit()
    }

    /// Takes the overlay out, then calls `completion` unless another transition has
    /// started meanwhile (the picker came back).
    func animateOut(_ animation: OverlayAnimation, duration: TimeInterval, completion: @escaping () -> Void) {
        guard let layer else {
            completion()
            return
        }
        let from = presentedOpacity
        let kind = effectiveKind(animation, duration: duration, resuming: from < 0.99)
        let token = beginTransition()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.transition == token else { return }
            completion()
        }
        layer.opacity = 0
        switch kind {
        case .none:
            break
        case .fade:
            addOpacity(from: from, to: 0, duration: duration * Double(from), timing: Self.easeIn)
        case .blur:
            addOpacity(from: from, to: 0, duration: duration * 0.7, timing: Self.easeIn)
            blurView.rampRadius(from: style?.blur ?? 0, to: 0, duration: duration, timing: Self.easeIn)
        case .iris:
            addIris(from: 1, to: irisClosedScale, duration: duration, timing: Self.easeIn)
            addOpacity(from: from, to: 0, duration: duration * 0.35, delay: duration * 0.65, timing: Self.easeIn)
        }
        CATransaction.commit()
    }

    /// A plain cross-fade to `opacity`, whatever the configured animations: used to
    /// step aside for a live preview and come back after.
    func fade(to opacity: Float, duration: TimeInterval) {
        guard let layer else { return }
        let from = presentedOpacity
        beginTransition()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        addOpacity(from: from, to: opacity, duration: duration, timing: CAMediaTimingFunction(name: .easeInEaseOut))
        CATransaction.commit()
    }

    // MARK: - Private

    /// The opacity on screen right now, mid-animation included.
    private var presentedOpacity: Float {
        layer?.presentation()?.opacity ?? layer?.opacity ?? 0
    }

    /// The iris scale at which the circle hides behind the picker.
    private var irisClosedScale: CGFloat {
        let reach = OverlayGeometry.coverRadius(from: focus, in: bounds.size) / Self.irisCore
        guard reach > 0 else { return 0.01 }
        return min(max(focusRadius / reach, 0.01), 1)
    }

    /// Resuming mid-way, or with nothing to animate (no blur for `blur`), falls back to
    /// a fade from where the overlay is.
    private func effectiveKind(
        _ animation: OverlayAnimation,
        duration: TimeInterval,
        resuming: Bool
    ) -> OverlayAnimation {
        guard duration > 0, animation != .none else { return .none }
        if resuming || (animation == .blur && (style?.blur ?? 0) <= 0) {
            return .fade
        }
        return animation
    }

    /// Cancels whatever transition is running and returns the new one's token.
    @discardableResult
    private func beginTransition() -> Int {
        transition += 1
        layer?.removeAnimation(forKey: Self.opacityKey)
        layer?.mask = nil
        blurView.cancelRamp()
        return transition
    }

    private func addOpacity(
        from: Float,
        to: Float,
        duration: TimeInterval,
        delay: TimeInterval = 0,
        timing: CAMediaTimingFunction
    ) {
        guard let layer, duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timing
        if delay > 0 {
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: Self.opacityKey)
    }

    /// A soft-edged circle mask around the picker, scaled from `from` to `to`.
    private func addIris(from: CGFloat, to: CGFloat, duration: TimeInterval, timing: CAMediaTimingFunction) {
        guard let layer else { return }
        let reach = OverlayGeometry.coverRadius(from: focus, in: bounds.size) / Self.irisCore
        let mask = CAGradientLayer()
        mask.type = .radial
        mask.colors = [1.0, 1.0, 0.0].map { CGColor(gray: 0, alpha: $0) }
        mask.locations = [0, NSNumber(value: Double(Self.irisCore)), 1]
        mask.startPoint = CGPoint(x: 0.5, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 1)
        mask.bounds = CGRect(x: 0, y: 0, width: reach * 2, height: reach * 2)
        mask.position = focus
        mask.transform = CATransform3DMakeScale(to, to, 1)
        layer.mask = mask

        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timing
        mask.add(animation, forKey: Self.irisKey)
    }
}
