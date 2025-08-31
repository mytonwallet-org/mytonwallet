import UIKit

public let kCAMediaTimingFunctionSpring = "CAAnimationUtilsSpringCurve"

@objc private class CALayerAnimationDelegate: NSObject, CAAnimationDelegate {
    private let keyPath: String?
    var completion: ((Bool) -> Void)?
    
    init(animation: CAAnimation, completion: ((Bool) -> Void)?) {
        if let animation = animation as? CABasicAnimation {
            self.keyPath = animation.keyPath
        } else {
            self.keyPath = nil
        }
        self.completion = completion
        
        super.init()
    }
    
    @objc func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        if let anim = anim as? CABasicAnimation {
            if anim.keyPath != self.keyPath {
                return
            }
        }
        if let completion = self.completion {
            completion(flag)
        }
    }
}

public extension CALayer {
    func makeAnimation(from: AnyObject,
                       to: AnyObject,
                       keyPath: String,
                       timingFunction: String,
                       duration: Double,
                       delay: Double = 0.0,
                       mediaTimingFunction: CAMediaTimingFunction? = nil,
                       removeOnCompletion: Bool = true,
                       additive: Bool = false,
                       completion: ((Bool) -> Void)? = nil) -> CAAnimation {
        if timingFunction == kCAMediaTimingFunctionSpring {
            let animation = makeSpringAnimation(keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.isRemovedOnCompletion = removeOnCompletion
            animation.fillMode = .forwards
            if let completion = completion {
                animation.delegate = CALayerAnimationDelegate(animation: animation, completion: completion)
            }
            
            let speed: Float = 1.0
            animation.speed = speed * Float(animation.duration / duration)
            animation.isAdditive = additive
            
            if !delay.isZero {
                animation.beginTime = CACurrentMediaTime() + delay
                animation.fillMode = .both
            }
            
            return animation
        } else {
            let speed: Float = 1.0
            
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            if let mediaTimingFunction = mediaTimingFunction {
                animation.timingFunction = mediaTimingFunction
            } else {
                animation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName(rawValue: timingFunction))
            }
            animation.isRemovedOnCompletion = removeOnCompletion
            animation.fillMode = .forwards
            animation.speed = speed
            animation.isAdditive = additive
            if let completion = completion {
                animation.delegate = CALayerAnimationDelegate(animation: animation, completion: completion)
            }
            
            if !delay.isZero {
                animation.beginTime = CACurrentMediaTime() + delay
                animation.fillMode = .both
            }
            
            return animation
        }
    }
    
    func animate(from: AnyObject,
                 to: AnyObject,
                 keyPath: String,
                 timingFunction: String,
                 duration: Double,
                 delay: Double = 0.0,
                 mediaTimingFunction: CAMediaTimingFunction? = nil,
                 removeOnCompletion: Bool = true,
                 additive: Bool = false,
                 completion: ((Bool) -> Void)? = nil) {
        let animation = self.makeAnimation(from: from, to: to, keyPath: keyPath, timingFunction: timingFunction, duration: duration, delay: delay, mediaTimingFunction: mediaTimingFunction, removeOnCompletion: removeOnCompletion, additive: additive, completion: completion)
        self.add(animation, forKey: additive ? nil : keyPath)
    }
    
    func animateAlpha(from: CGFloat,
                      to: CGFloat,
                      duration: Double,
                      delay: Double = 0.0,
                      timingFunction: String = CAMediaTimingFunctionName.easeInEaseOut.rawValue,
                      mediaTimingFunction: CAMediaTimingFunction? = nil,
                      removeOnCompletion: Bool = true,
                      completion: ((Bool) -> ())? = nil) {
        self.animate(from: NSNumber(value: Float(from)), to: NSNumber(value: Float(to)), keyPath: "opacity", timingFunction: timingFunction, duration: duration, delay: delay, mediaTimingFunction: mediaTimingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
    }
    
}

/// Disable implicit animations on a layer by setting layer.actions = noAnim
public let noAnim: [String: CAAction] = [
    "bounds": NSNull(),
    "frame": NSNull(),
    "position": NSNull(),
]
