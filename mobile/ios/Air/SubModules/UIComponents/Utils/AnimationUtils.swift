//
//  AnimationUtils.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/12/24.
//

import UIKit

public class ValueAnimator {
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

    private lazy var springAnimation = makeSpringAnimation("", initialVelocity: initialVelocity)

    private var updateBlock: ((_ progress: CGFloat, _ value: CGFloat) -> Void)?
    private var completionBlock: (() -> Void)?

    public init(startValue: CGFloat,
                endValue: CGFloat,
                duration: TimeInterval,
                initialVelocity: CGFloat = 0,
                animationType: AnimationType = .spring) {
        self.startValue = startValue
        self.endValue = endValue
        self.duration = duration
        self.initialVelocity = initialVelocity
        self.animationType = animationType
        self.prevProgress = -1
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
        let fraction = min(elapsedTime / duration, 1.0)
        
        var progress: CGFloat
        switch animationType {
        case .spring:
            progress = springAnimation.value(at: fraction)
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
