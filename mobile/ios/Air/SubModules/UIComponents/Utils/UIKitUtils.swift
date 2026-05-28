//
//  UIViewUtils.swift
//  UIComponents
//
//  Created by Sina on 4/13/23.
//

import UIKit

public extension UIView {
    func shake(duration: CFTimeInterval = 0.3, repeatCount: Float = 2, amplitude: CGFloat = 4) {
        let animation = CABasicAnimation(keyPath: "position")
        animation.duration = duration / TimeInterval(repeatCount * 2)
        animation.repeatCount = repeatCount
        animation.autoreverses = true
        animation.fromValue = NSValue(cgPoint: CGPoint(x: self.center.x - amplitude, y: self.center.y))
        animation.toValue = NSValue(cgPoint: CGPoint(x: self.center.x + amplitude, y: self.center.y))
        self.layer.add(animation, forKey: "shake")
    }
    static func easeInOut(_ t: Float, _ b: Float, _ c: Float, _ d: Float = 1.0) -> Float {
        var t2 = t / (d / 2.0)
        if t2 < 1 {
            return c / 2 * t2 * t2 * t2 + b
        } else {
            t2 -= 2
            return c / 2 * (t2 * t2 * t2 + 2) + b
        }
    }
}

public func makeSpringAnimation(_ keyPath: String, initialVelocity: CGFloat = 0) -> CASpringAnimation {
    return _makeSpringAnimationImpl(keyPath, initialVelocity: initialVelocity)
}

private func _makeSpringAnimationImpl(_ keyPath: String, initialVelocity: CGFloat = 0) -> CASpringAnimation {
    let springAnimation = CASpringAnimation(keyPath: keyPath)
    springAnimation.mass = 3.0
    springAnimation.stiffness = 1000.0
    springAnimation.damping = 500.0
    springAnimation.duration = 0.5
    springAnimation.initialVelocity = initialVelocity
    springAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.linear)
    return springAnimation
}

extension CGSize {
    func fitted(_ size: CGSize) -> CGSize {
        var fittedSize = self
        if fittedSize.width > size.width {
            fittedSize = CGSize(width: size.width, height: floor((fittedSize.height * size.width / max(fittedSize.width, 1.0))))
        }
        if fittedSize.height > size.height {
            fittedSize = CGSize(width: floor((fittedSize.width * size.height / max(fittedSize.height, 1.0))), height: size.height)
        }
        return fittedSize
    }
    func aspectFitted(_ size: CGSize) -> CGSize {
        let scale = min(size.width / max(1.0, self.width), size.height / max(1.0, self.height))
        return CGSize(width: floor(self.width * scale), height: floor(self.height * scale))
    }
    
    func aspectFilled(_ size: CGSize) -> CGSize {
        let scale = max(size.width / max(1.0, self.width), size.height / max(1.0, self.height))
        return CGSize(width: floor(self.width * scale), height: floor(self.height * scale))
    }
}

public extension CGRect {
    var center: CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}

public extension String {
    func height(withFont font: UIFont, width: CGFloat) -> CGFloat {
        let constraintRect = CGSize(width: width, height: .greatestFiniteMagnitude)
        let boundingBox = NSString(string: self).boundingRect(with: constraintRect,
                                                              options: .usesLineFragmentOrigin,
                                                              attributes: [.font: font],
                                                              context: nil)
        return ceil(boundingBox.height)
    }
}

public extension UIDevice {
    var hasDynamicIsland: Bool {
        guard userInterfaceIdiom == .phone else {
            return false
        }
        guard let window = UIApplication.shared.sceneKeyWindow else {
            return false
        }
        return window.safeAreaInsets.top >= 51
    }
}


public extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
