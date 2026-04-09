import UIKit

enum ContextMenuAnimationSupport {
    static let springMass: CGFloat = 5.0
    static let springStiffness: CGFloat = 900.0
    static let appearDuration: CFTimeInterval = 0.42
    static let appearDamping: CGFloat = 104.0
    static let disappearDuration: CFTimeInterval = 0.2
}

extension CALayer {
    func addContextMenuSpringAnimation(
        keyPath: String,
        from: Any,
        to: Any,
        duration: CFTimeInterval,
        damping: CGFloat,
        additive: Bool
    ) {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = ContextMenuAnimationSupport.springMass
        animation.stiffness = ContextMenuAnimationSupport.springStiffness
        animation.damping = damping
        animation.initialVelocity = 0.0
        animation.fromValue = from
        animation.toValue = to
        animation.isAdditive = additive
        animation.timingFunction = CAMediaTimingFunction(name: .linear)

        let settlingDuration = animation.settlingDuration
        animation.duration = settlingDuration
        if duration > 0.0, settlingDuration > 0.0 {
            animation.speed = Float(settlingDuration / duration)
        }

        self.add(animation, forKey: keyPath + ".contextMenuSpring")
    }

    func addContextMenuBasicAnimation(
        keyPath: String,
        from: Any,
        to: Any,
        duration: CFTimeInterval,
        timingFunction: CAMediaTimingFunctionName,
        additive: Bool = false,
        removeOnCompletion: Bool = true
    ) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timingFunction)
        animation.isAdditive = additive
        animation.isRemovedOnCompletion = removeOnCompletion
        if !removeOnCompletion {
            animation.fillMode = .forwards
        }
        self.add(animation, forKey: keyPath + ".contextMenuBasic")
    }

    func addContextMenuAlphaAnimation(
        from: CGFloat,
        to: CGFloat,
        duration: CFTimeInterval,
        removeOnCompletion: Bool = true
    ) {
        self.addContextMenuBasicAnimation(
            keyPath: "opacity",
            from: from as NSNumber,
            to: to as NSNumber,
            duration: duration,
            timingFunction: .linear,
            removeOnCompletion: removeOnCompletion
        )
    }
}
