//
//  AnimationUtils.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/12/24.
//

import UIKit

@MainActor public class ValueAnimator {
    public enum AnimationType {
        case spring
        case easeInOut
    }
    
    private var startValue: CGFloat
    private var endValue: CGFloat
    private var duration: TimeInterval
    private var initialVelocity: CGFloat
    private var startTime: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var prevProgress: CGFloat
    private var animationType: AnimationType
    private let springCurve: SpringCurve?

    private var updateBlock: ((_ progress: CGFloat, _ value: CGFloat) -> Void)?
    private var completionBlock: (() -> Void)?

    public init(startValue: CGFloat,
                endValue: CGFloat,
                duration: TimeInterval,
                initialVelocity: CGFloat = 0,
                animationType: AnimationType = .spring,
                dampingRatio: CGFloat? = nil) {
        self.startValue = startValue
        self.endValue = endValue
        self.duration = duration
        self.initialVelocity = initialVelocity
        self.animationType = animationType
        self.prevProgress = -1
        if animationType == .spring {
            if let dampingRatio {
                springCurve = SpringCurve(
                    initialVelocity: initialVelocity,
                    dampingRatio: dampingRatio,
                    referenceDuration: CGFloat(duration)
                )
            } else {
                springCurve = SpringCurve(initialVelocity: initialVelocity)
            }
        } else {
            springCurve = nil
        }
    }

    public func addUpdateBlock(_ block: @escaping (_ progress: CGFloat, _ value: CGFloat) -> Void) {
        self.updateBlock = block
    }

    public func addCompletionBlock(_ block: @escaping () -> Void) {
        self.completionBlock = block
    }

    public func start() {
        startTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30.0, maximum: 120.0, preferred: 120.0)
        }
        displayLink?.add(to: .main, forMode: .common)
    }
    
    public func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func update() {
        guard let startTime = self.startTime else { return }
        
        let elapsedTime = CACurrentMediaTime() - startTime
        let fraction: CGFloat = duration > 0 ? min(elapsedTime / duration, 1.0) : 1.0
        
        var progress: CGFloat
        switch animationType {
        case .spring:
            progress = springCurve?.value(at: fraction) ?? fraction
        case .easeInOut:
            progress = CGFloat(UIView.easeInOut(Float(fraction), Float(), Float(1)))
        }

        if progress > 0.998 && progress == prevProgress {
            progress = 1
        } else {
            prevProgress = progress
        }

        let currentValue = startValue + (endValue - startValue) * progress
        
        updateBlock?(progress, currentValue)
        
        if progress >= 1.0 {
            displayLink?.invalidate()
            displayLink = nil
            completionBlock?()
        }
    }
}

@MainActor public final class DisplayLinkAlphaAnimator {
    private weak var view: UIView?
    private var animator: ValueAnimator?

    public init(view: UIView) {
        self.view = view
    }

    public func setAlpha(_ targetAlpha: CGFloat, animated: Bool, duration: TimeInterval = 0.3) {
        animator?.invalidate()

        let targetAlpha = min(max(targetAlpha, 0), 1)
        guard let view else { return }

        guard animated else {
            setAlphaImmediately(targetAlpha)
            return
        }

        let currentAlpha = CGFloat(view.layer.presentation()?.opacity ?? view.layer.opacity)
        guard abs(currentAlpha - targetAlpha) > 0.001 else {
            setAlphaImmediately(targetAlpha)
            return
        }

        setAlphaImmediately(currentAlpha)

        let animator = ValueAnimator(
            startValue: currentAlpha,
            endValue: targetAlpha,
            duration: duration,
            animationType: .easeInOut
        )
        self.animator = animator

        animator.addUpdateBlock { [weak self] _, alpha in
            self?.setAlphaImmediately(alpha)
        }
        animator.addCompletionBlock { [weak self, weak animator] in
            guard let self, self.animator === animator else { return }
            self.setAlphaImmediately(targetAlpha)
            self.animator = nil
        }
        animator.start()
    }

    public func invalidate() {
        animator?.invalidate()
        animator = nil
    }

    private func setAlphaImmediately(_ alpha: CGFloat) {
        guard let view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.alpha = min(max(alpha, 0), 1)
        CATransaction.commit()
    }
}

private struct SpringCurve {
    private let mass: CGFloat
    private let stiffness: CGFloat
    private let damping: CGFloat
    private let initialVelocity: CGFloat
    private let referenceDuration: CGFloat
    private let finalProgress: CGFloat

    init(initialVelocity: CGFloat) {
        let animation = makeSpringAnimation("", initialVelocity: initialVelocity)
        self.init(
            initialVelocity: initialVelocity,
            mass: animation.mass,
            stiffness: animation.stiffness,
            damping: animation.damping,
            referenceDuration: animation.duration
        )
    }

    init(
        initialVelocity: CGFloat,
        dampingRatio: CGFloat,
        mass: CGFloat = 1.0,
        stiffness: CGFloat = 280.0,
        referenceDuration: CGFloat
    ) {
        let damping = dampingRatio * 2 * sqrt(stiffness * mass)
        self.init(
            initialVelocity: initialVelocity,
            mass: mass,
            stiffness: stiffness,
            damping: damping,
            referenceDuration: referenceDuration
        )
    }

    private init(
        initialVelocity: CGFloat,
        mass: CGFloat,
        stiffness: CGFloat,
        damping: CGFloat,
        referenceDuration: CGFloat
    ) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
        self.initialVelocity = initialVelocity
        self.referenceDuration = max(referenceDuration, .ulpOfOne)
        self.finalProgress = max(
            SpringCurve.rawProgress(
                at: self.referenceDuration,
                mass: mass,
                stiffness: stiffness,
                damping: damping,
                initialVelocity: initialVelocity
            ),
            .ulpOfOne
        )
    }

    func value(at fraction: CGFloat) -> CGFloat {
        let clampedFraction = max(0, min(1, fraction))
        let time = referenceDuration * clampedFraction
        let progress = rawProgress(at: time) / finalProgress
        return min(max(progress, 0), 1)
    }

    private func rawProgress(at time: CGFloat) -> CGFloat {
        SpringCurve.rawProgress(
            at: time,
            mass: mass,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity
        )
    }

    private static func rawProgress(
        at time: CGFloat,
        mass: CGFloat,
        stiffness: CGFloat,
        damping: CGFloat,
        initialVelocity: CGFloat
    ) -> CGFloat {
        1 - displacement(
            at: time,
            mass: mass,
            stiffness: stiffness,
            damping: damping,
            initialVelocity: initialVelocity
        )
    }

    private static func displacement(
        at time: CGFloat,
        mass: CGFloat,
        stiffness: CGFloat,
        damping: CGFloat,
        initialVelocity: CGFloat
    ) -> CGFloat {
        guard mass > 0, stiffness > 0 else {
            return max(0, 1 - time)
        }

        let y0: CGFloat = 1
        let yPrime0 = -initialVelocity
        let naturalFrequency = sqrt(stiffness / mass)
        let dampingRatio = damping / (2 * sqrt(stiffness * mass))

        if dampingRatio > 1.0001 {
            let sqrtTerm = sqrt(dampingRatio * dampingRatio - 1)
            let r1 = -naturalFrequency * (dampingRatio - sqrtTerm)
            let r2 = -naturalFrequency * (dampingRatio + sqrtTerm)
            let c1 = (yPrime0 - r2 * y0) / (r1 - r2)
            let c2 = y0 - c1
            return c1 * exp(r1 * time) + c2 * exp(r2 * time)
        }

        if dampingRatio < 0.9999 {
            let dampedFrequency = naturalFrequency * sqrt(1 - dampingRatio * dampingRatio)
            let coefficient = (yPrime0 + dampingRatio * naturalFrequency * y0) / dampedFrequency
            return exp(-dampingRatio * naturalFrequency * time) * (
                y0 * cos(dampedFrequency * time) + coefficient * sin(dampedFrequency * time)
            )
        }

        let coefficient = yPrime0 + naturalFrequency * y0
        return (y0 + coefficient * time) * exp(-naturalFrequency * time)
    }
}
