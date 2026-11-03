import UIKit
import WalletContext

/// A loading placeholder swept by a soft highlight, which fades out as the loaded content replaces it. A subclass
/// draws its shapes, colors them in `updateColors` and runs the highlight in `startShimmer`.
class AgentSkeletonView: UIView {
    static let shimmerKey = "shimmer"
    /// Keeps the layers from animating their geometry implicitly
    static let noImplicitGeometry: [String: CAAction] = [
        "path": NSNull(),
        "frame": NSNull(),
        "bounds": NSNull(),
        "position": NSNull(),
    ]

    private let fadeDuration: TimeInterval
    private var isVisibleTarget = true

    /// On screen and not fading out
    var isShowing: Bool { isVisibleTarget && !isHidden }

    init(fadeDuration: TimeInterval) {
        self.fadeDuration = fadeDuration
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = lang("Loading...")
        accessibilityTraits = .updatesFrequently
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { startShimmer() } else { stopShimmer() }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        updateColors()
    }

    /// Shows or hides the placeholder, fading it out as the loaded content replaces it
    func setVisible(_ isVisible: Bool, animated: Bool) {
        guard isVisible != isVisibleTarget || isVisible && isHidden || !isVisible && !animated && !isHidden else { return }
        isVisibleTarget = isVisible
        layer.removeAllAnimations()
        guard !isVisible, animated, !isHidden, !UIAccessibility.isReduceMotionEnabled else {
            alpha = 1
            isHidden = !isVisible
            return
        }
        UIView.animate(withDuration: fadeDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.alpha = 0
        } completion: { [weak self] _ in
            guard let self, !self.isVisibleTarget else { return }
            self.isHidden = true
            self.alpha = 1
        }
    }

    func updateColors() {}

    func startShimmer(isRestarting: Bool = false) {}

    func stopShimmer() {}

    /// Moves `band` by `travel` points along `keyPath` every `duration`, slowing down as it goes. A running sweep goes
    /// on, unless `isRestarting` and its travel changed.
    func startSweep(of band: CALayer, along keyPath: String, travel: CGFloat, duration: CFTimeInterval, isRestarting: Bool) {
        if let running = band.animation(forKey: Self.shimmerKey) as? CABasicAnimation,
           !isRestarting || (running.toValue as? CGFloat) == travel {
            return
        }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = CGFloat(0)
        animation.toValue = travel
        animation.isAdditive = true
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        band.add(animation, forKey: Self.shimmerKey)
    }
}
