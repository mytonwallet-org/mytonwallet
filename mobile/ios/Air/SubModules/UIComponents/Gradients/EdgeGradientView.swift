import UIKit

/// A configurable edge fade view backed by `CAGradientLayer`.
/// It renders from `color` to transparent along `direction`,
/// with an optional solid segment (`solidEdgeLength`) at the opaque edge.
public final class EdgeGradientView: UIView {
    public enum Direction {
        case leading
        case trailing
        case top
        case bottom
    }
    
    public override class var layerClass: AnyClass { CAGradientLayer.self }
    
    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }
    
    public var color: UIColor = .clear {
        didSet {
            applyColors()
        }
    }
    
    public var direction: Direction = .leading {
        didSet {
            applyDirection()
        }
    }
    
    public var solidEdgeLength: CGFloat = 0 {
        didSet {
            applyColors()
        }
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
        applyDirection()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        applyColors()
    }
    
    private func setup() {
        isUserInteractionEnabled = false
        applyColors()
        applyDirection()
    }
    
    private func applyColors() {
        let transparentColor = color.withAlphaComponent(0).cgColor
        let solidColor = color.cgColor
        let axisLength: CGFloat = switch direction {
        case .leading, .trailing:
            bounds.width
        case .top, .bottom:
            bounds.height
        }
        let safeAxisLength = max(axisLength, 1)
        let solidRatio = max(0, min(1, solidEdgeLength / safeAxisLength))
        
        gradientLayer.colors = [
            solidColor,
            solidColor,
            transparentColor
        ]
        gradientLayer.locations = [
            0 as NSNumber,
            NSNumber(value: solidRatio),
            1 as NSNumber
        ]
    }
    
    private func applyDirection() {
        switch direction {
        case .leading:
            if effectiveUserInterfaceLayoutDirection == .rightToLeft {
                gradientLayer.startPoint = CGPoint(x: 1, y: 0.5)
                gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)
            } else {
                gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
                gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            }
        case .trailing:
            if effectiveUserInterfaceLayoutDirection == .rightToLeft {
                gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
                gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            } else {
                gradientLayer.startPoint = CGPoint(x: 1, y: 0.5)
                gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)
            }
        case .top:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        case .bottom:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        }
    }
}
