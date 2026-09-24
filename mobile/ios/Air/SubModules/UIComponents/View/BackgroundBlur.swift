import SwiftUI
import UIKit

public struct BackgroundBlur: UIViewRepresentable {
    
    public var radius: CGFloat
    
    public init(radius: CGFloat) {
        self.radius = radius
    }
    
    public func makeUIView(context: Context) -> BackgroundBlurView {
        BackgroundBlurView(radius: radius)
    }

    public func updateUIView(_ uiView: BackgroundBlurView, context: Context) {
        uiView.blurRadius = radius
    }
}

open class BackgroundBlurView: UIVisualEffectView {

    private static let blurRadiusKeyPath = "filters.gaussianBlur.inputRadius"
    private static let blurRadiusAnimationKey = "BackgroundBlurView.blurRadius"
    
    /// The model blur radius. Assign inside a `UIView` animation block to animate the change.
    public var blurRadius: CGFloat {
        get { radius(on: blurLayer) }
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
                blurLayer?.removeAnimation(forKey: Self.blurRadiusAnimationKey)
                applyRadius(newValue)
            }
        }
    }

    /// The radius currently visible on screen while an animation is in flight.
    public var presentationBlurRadius: CGFloat {
        radius(on: blurLayer?.presentation() ?? blurLayer)
    }

    private weak var blurLayer: CALayer?
    
    public init(radius: CGFloat) {
        super.init(effect: UIBlurEffect(style: .regular))
        for subview in subviews {
            if NSStringFromClass(type(of: subview)).contains("VisualEffectSubview") {
                subview.isHidden = true
            }
        }
        if let sublayer = layer.sublayers?.first, let filters = sublayer.filters {
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            sublayer.filters = filters.filter { ($0 as? NSObject)?.description == "gaussianBlur" }
            // The backdrop layer defaults to heavily downsampled rendering, which is visible near radius zero.
            sublayer.setValue(1 as NSNumber, forKey: "scale")
            self.blurLayer = sublayer
        }
        applyRadius(max(0, radius))
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // prevent effects reenabling
    }

    /// Animates the filter directly when explicit Core Animation control is preferable.
    public func animateBlurRadius(
        to radius: CGFloat,
        duration: TimeInterval,
        timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    ) {
        guard let blurLayer else { return }

        let radius = max(0, radius)
        let fromRadius = presentationBlurRadius
        blurLayer.removeAnimation(forKey: Self.blurRadiusAnimationKey)
        applyRadius(radius)

        guard duration > 0, fromRadius != radius else { return }

        let animation = CABasicAnimation(keyPath: Self.blurRadiusKeyPath)
        animation.fromValue = fromRadius
        animation.toValue = radius
        animation.duration = duration
        animation.timingFunction = timingFunction
        blurLayer.add(animation, forKey: Self.blurRadiusAnimationKey)
    }

    /// Stops an in-flight animation at its currently visible radius.
    public func removeBlurRadiusAnimation() {
        guard let blurLayer else { return }
        let currentRadius = radius(on: blurLayer.presentation() ?? blurLayer)
        blurLayer.removeAnimation(forKey: Self.blurRadiusAnimationKey)
        applyRadius(currentRadius)
    }

    private func radius(on layer: CALayer?) -> CGFloat {
        guard let number = layer?.value(forKeyPath: Self.blurRadiusKeyPath) as? NSNumber else {
            return 0
        }
        return CGFloat(truncating: number)
    }

    private func setRadius(_ radius: CGFloat, on layer: CALayer?) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(radius as NSNumber, forKeyPath: Self.blurRadiusKeyPath)
        CATransaction.commit()
    }

    private func applyRadius(_ radius: CGFloat) {
        setRadius(radius, on: blurLayer)
    }
}
