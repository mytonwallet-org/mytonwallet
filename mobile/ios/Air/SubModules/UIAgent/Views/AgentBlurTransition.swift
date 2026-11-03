import UIKit
import UIComponents

/// Content that comes into focus as it arrives and blurs away as it leaves, drifting a little on the way.
///
/// The animations are added to the layers directly, so they also play when the change happens inside a list update
/// that runs without UIKit animations.
@MainActor
enum AgentBlurTransition {
    /// The blur at the far end of the transition
    static let radius: CGFloat = 8

    private static let animationKey = "agentBlurTransition"
    private static let blurRadiusKeyPath = "filters.gaussianBlur.inputRadius"

    /// Fades `layer` in from transparency, from `radius` of blur unless `shouldSkipBlur` is set, and from `drift`
    /// points below its place. `completion` runs once it is in focus, unless a later transition on the layer replaced
    /// this one.
    static func animateIn(
        _ layer: CALayer,
        duration: CFTimeInterval,
        delay: CFTimeInterval = 0,
        drift: CGFloat = 0,
        shouldSkipBlur: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        animate(layer, isAppearing: true, duration: duration, delay: delay, drift: drift, shouldBlur: !shouldSkipBlur, completion: completion)
    }

    /// Fades `layer` out into `radius` of blur unless `shouldSkipBlur` is set, drifting it by `drift` points. It stays
    /// transparent afterwards; `completion` runs at the end, or when a later transition on the layer replaces this one.
    static func animateOut(
        _ layer: CALayer,
        duration: CFTimeInterval,
        drift: CGFloat = 0,
        shouldSkipBlur: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        animate(layer, isAppearing: false, duration: duration, delay: 0, drift: drift, shouldBlur: !shouldSkipBlur, completion: completion)
    }

    /// Stops a running transition and brings the layer back in focus where it stands
    static func cancel(_ layer: CALayer) {
        layer.removeAnimation(forKey: animationKey)
        removeBlur(from: layer)
    }

    private static func animate(
        _ layer: CALayer,
        isAppearing: Bool,
        duration: CFTimeInterval,
        delay: CFTimeInterval,
        drift: CGFloat,
        shouldBlur: Bool,
        completion: (() -> Void)?
    ) {
        layer.removeAnimation(forKey: animationKey)
        removeBlur(from: layer)
        var animations: [CAAnimation] = []

        // The layer takes its final state at once, without implicit animations; the explicit ones below lead to it
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = isAppearing ? 0 : 1
        opacity.toValue = isAppearing ? 1 : 0
        animations.append(opacity)
        layer.opacity = isAppearing ? 1 : 0

        if shouldBlur, let blur = WBlurredContentView.makeGaussianBlurFilter() {
            blur.setValue(isAppearing ? 0 : radius, forKey: "inputRadius")
            layer.filters = [blur]
            let radiusAnimation = CABasicAnimation(keyPath: blurRadiusKeyPath)
            radiusAnimation.fromValue = isAppearing ? radius : 0
            radiusAnimation.toValue = isAppearing ? 0 : radius
            animations.append(radiusAnimation)
        }

        if drift != 0 {
            let position = CABasicAnimation(keyPath: "position.y")
            position.isAdditive = true
            position.fromValue = isAppearing ? drift : 0
            position.toValue = isAppearing ? 0 : drift
            animations.append(position)
        }

        for animation in animations {
            animation.duration = duration
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.beginTime = delay > 0 ? layer.convertTime(CACurrentMediaTime(), from: nil) + delay : 0
        group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(name: isAppearing ? .easeOut : .easeIn)
        group.delegate = CompletionDelegate { [weak layer] finished in
            guard isAppearing else {
                completion?()
                return
            }
            // A transition that replaced this one keeps its blur
            guard finished else { return }
            if let layer { removeBlur(from: layer) }
            completion?()
        }
        layer.add(group, forKey: animationKey)
    }

    private static func removeBlur(from layer: CALayer) {
        guard layer.filters != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.filters = nil
        CATransaction.commit()
    }

    private final class CompletionDelegate: NSObject, CAAnimationDelegate {
        private let completion: @MainActor (Bool) -> Void

        init(completion: @escaping @MainActor (Bool) -> Void) {
            self.completion = completion
        }

        nonisolated func animationDidStop(_ animation: CAAnimation, finished: Bool) {
            MainActor.assumeIsolated { completion(finished) }
        }
    }
}
