
import UIKit


public final class WBlurredContentView: UIView {
    public var passesTouchesOutsideContent = false

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return passesTouchesOutsideContent && hit === self ? nil : hit
    }


    private static let blurRadiusKeyPath = "filters.gaussianBlur.inputRadius"
    private static let blurRadiusAnimationKey = "WBlurredContentView.blurRadius"

    public var blurRadius: CGFloat {
        get { radius(on: layer) }
        set {
            let newValue = max(0, newValue)
            let duration = UIView.inheritedAnimationDuration
            if duration > 0 {
                animateBlurRadius(
                    to: newValue,
                    duration: duration,
                    timingFunction: CATransaction.animationTimingFunction()
                        ?? CAMediaTimingFunction(name: .easeInEaseOut)
                )
            } else {
                layer.removeAnimation(forKey: Self.blurRadiusAnimationKey)
                setRadius(newValue, on: layer)
            }
        }
    }

    public var presentationBlurRadius: CGFloat {
        radius(on: layer.presentation() ?? layer)
    }

    public init() {
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        if let gaussianBlur = Self.makeGaussianBlurFilter() {
            layer.filters = [gaussianBlur]
        }
    }

    /// A Gaussian blur for a layer's `filters`, at radius 0. Its radius lives at `filters.gaussianBlur.inputRadius`.
    public static func makeGaussianBlurFilter() -> NSObject? {
        guard let gaussianBlur = PrivateAPI.makeFilter("gaussianBlur") else { return nil }
        gaussianBlur.setValue(0.0, forKey: "inputRadius")
        return gaussianBlur
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func animateBlurRadius(
        to radius: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    ) {
        let radius = max(0, radius)
        let fromRadius = presentationBlurRadius
        layer.removeAnimation(forKey: Self.blurRadiusAnimationKey)
        setRadius(radius, on: layer)

        guard duration > 0, fromRadius != radius else { return }

        let animation = CABasicAnimation(keyPath: Self.blurRadiusKeyPath)
        animation.fromValue = fromRadius
        animation.toValue = radius
        animation.duration = duration
        animation.timingFunction = timingFunction
        layer.add(animation, forKey: Self.blurRadiusAnimationKey)
    }

    public func removeBlurRadiusAnimation() {
        let currentRadius = presentationBlurRadius
        layer.removeAnimation(forKey: Self.blurRadiusAnimationKey)
        setRadius(currentRadius, on: layer)
    }

    private func radius(on layer: CALayer) -> CGFloat {
        if let number = layer.value(forKeyPath: Self.blurRadiusKeyPath) as? NSNumber {
            return CGFloat(truncating: number)
        }
        return layer === self.layer ? 0 : radius(on: self.layer)
    }

    private func setRadius(_ radius: CGFloat, on layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(radius as NSNumber, forKeyPath: Self.blurRadiusKeyPath)
        CATransaction.commit()
    }
}
