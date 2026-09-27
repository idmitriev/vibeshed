import AppKit
import QuartzCore

/// Behind-window blur with a chosen radius and saturation.
///
/// NSVisualEffectView blurs through a window-server-aware `CABackdropLayer` whose filters
/// are named `gaussianBlur` (30pt for every material as of macOS 27) and `colorSaturate`.
/// Those names are private, so they're looked up rather than assumed: if a later macOS
/// renames them, the material's own blur shows instead and nothing breaks. AppKit builds
/// that layer tree in `updateLayer()` a frame after the window is ordered in, and builds
/// a new one on every appearance or material change, so the tuning is applied there.
final class BackdropBlurView: NSVisualEffectView {
    struct Tuning: Equatable {
        var radius: Double
        var saturation: Double
        /// Keep the material's own tint layers (fill, tone, desktop tint) over the blur.
        var showsMaterialTint: Bool
    }

    var tuning = Tuning(radius: 30, saturation: 1.8, showsMaterialTint: true) {
        didSet {
            if tuning != oldValue { applyTuning() }
        }
    }

    private static let radiusKeyPath = "filters.gaussianBlur.inputRadius"
    private static let saturationKeyPath = "filters.colorSaturate.inputAmount"
    private static let rampKey = "overlay.blurRamp"

    /// A radius ramp asked for before AppKit built the backdrop (the first show). It's
    /// attached once the layer exists, with its original start time, so it stays in step
    /// with the fade it was started alongside.
    private var pendingRamp: CABasicAnimation?
    private var loggedMissingFilters = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blendingMode = .behindWindow
        state = .active
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateLayer() {
        super.updateLayer()
        applyTuning()
        if let ramp = pendingRamp, let backdrop = backdropLayer {
            pendingRamp = nil
            attach(ramp, to: backdrop)
        }
    }

    /// Animates the blur radius — the focus pull of the `blur` animation. The model
    /// radius stays `tuning.radius`, so the ramp should end there (show) or end hidden.
    func rampRadius(from: Double, to: Double, duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        let ramp = CABasicAnimation(keyPath: Self.radiusKeyPath)
        ramp.fromValue = from
        ramp.toValue = to
        ramp.duration = duration
        ramp.timingFunction = timing
        ramp.beginTime = CACurrentMediaTime()
        ramp.fillMode = .both
        if let backdrop = backdropLayer {
            attach(ramp, to: backdrop)
        } else {
            pendingRamp = ramp
        }
    }

    func cancelRamp() {
        pendingRamp = nil
        backdropLayer?.removeAnimation(forKey: Self.rampKey)
    }

    /// Whether AppKit has built the blur yet (it does so on the window's first display).
    var hasBackdrop: Bool {
        backdropLayer != nil
    }

    // MARK: - Private

    private var backdropLayer: CALayer? {
        Self.findBackdrop(in: layer)
    }

    private func attach(_ ramp: CABasicAnimation, to backdrop: CALayer) {
        guard Self.hasFilter("gaussianBlur", on: backdrop) else { return }
        // Media time → the layer's time space, so a late attach picks up mid-ramp.
        ramp.beginTime = backdrop.convertTime(ramp.beginTime, from: nil)
        backdrop.add(ramp, forKey: Self.rampKey)
    }

    private func applyTuning() {
        guard let backdrop = backdropLayer else { return }
        let canBlur = Self.hasFilter("gaussianBlur", on: backdrop)
        let canSaturate = Self.hasFilter("colorSaturate", on: backdrop)
        if !(canBlur && canSaturate), !loggedMissingFilters {
            loggedMissingFilters = true
            let names = (backdrop.filters ?? []).compactMap { ($0 as? NSObject)?.description }
            let message = "Backdrop filters changed (\(names)); the overlay falls back to the material's blur"
            Log.picker.warning("\(message, privacy: .public)")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if canBlur {
            backdrop.setValue(tuning.radius, forKeyPath: Self.radiusKeyPath)
        }
        if canSaturate {
            backdrop.setValue(tuning.saturation, forKeyPath: Self.saturationKeyPath)
        }
        if backdrop.responds(to: NSSelectorFromString("setScale:")) {
            backdrop.setValue(Self.captureScale(forRadius: tuning.radius), forKey: "scale")
        }
        for sibling in backdrop.superlayer?.sublayers ?? [] where sibling !== backdrop {
            sibling.isHidden = !tuning.showsMaterialTint
        }
        CATransaction.commit()
        // Read back from the layer, so the log shows what the render server was given.
        let radius = canBlur ? backdrop.value(forKeyPath: Self.radiusKeyPath) ?? "-" : "-"
        let saturation = canSaturate ? backdrop.value(forKeyPath: Self.saturationKeyPath) ?? "-" : "-"
        let message = "Backdrop tuned: radius \(radius), saturation \(saturation), "
            + "tint \(tuning.showsMaterialTint ? "shown" : "hidden")"
        Log.picker.debug("\(message, privacy: .public)")
    }

    /// Materials capture what's behind at 1/8 scale for their 30pt blur. Smaller radii
    /// keep that radius-to-sample ratio instead, or a light blur would look blocky.
    static func captureScale(forRadius radius: Double) -> Double {
        guard radius > 0 else { return 1 }
        return min(1, max(0.125, 3.75 / radius))
    }

    private static func findBackdrop(in layer: CALayer?) -> CALayer? {
        guard let layer else { return nil }
        if NSStringFromClass(type(of: layer)) == "CABackdropLayer" { return layer }
        for sublayer in layer.sublayers ?? [] {
            if let backdrop = findBackdrop(in: sublayer) { return backdrop }
        }
        return nil
    }

    /// Whether `layer` has a filter called `name` — checked before any `filters.<name>`
    /// key path, which raises for a missing filter.
    private static func hasFilter(_ name: String, on layer: CALayer) -> Bool {
        (layer.filters ?? []).contains { filter in
            guard let object = filter as? NSObject, object.responds(to: NSSelectorFromString("name")) else {
                return false
            }
            return object.value(forKey: "name") as? String == name
        }
    }
}

extension OverlayMaterial {
    /// The material hosting the blur. With `none` its tint layers are hidden, leaving
    /// only the backdrop.
    var visualEffectMaterial: NSVisualEffectView.Material {
        switch self {
        case .none, .fullScreen: .fullScreenUI
        case .hud: .hudWindow
        case .popover: .popover
        case .menu: .menu
        case .sidebar: .sidebar
        case .underWindow: .underWindowBackground
        }
    }
}
