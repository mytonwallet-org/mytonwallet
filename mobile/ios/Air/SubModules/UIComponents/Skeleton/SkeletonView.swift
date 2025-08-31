//
//  SkeletonView.swift
//  UIComponents
//
//  Created by Sina on 7/7/24.
//

import UIKit
import WalletContext

public class SkeletonView: UIView, WThemedView {
    
    private var gradientLayer: CAGradientLayer!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public let colors: [UIColor] = [UIColor.white.withAlphaComponent(0), UIColor.white.withAlphaComponent(0.3)]
    
    public func setupView(vertical: Bool) {
        gradientLayer = CAGradientLayer()
        if vertical {
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        } else {
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        }
        gradientLayer.locations = [0.0, 0.5, 1.0]

        layer.addSublayer(gradientLayer)
        
        updateTheme()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = bounds
    }
    
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if isAnimating {
            startAnimating()
        } else {
            stopAnimating()
        }
    }

    public private(set) var isAnimating: Bool = false
    public func startAnimating() {
        isHidden = false
        isAnimating = true
        if gradientLayer.animation(forKey: "skeletonAnimation") != nil {
            return
        }
        let keyframeAnimation = CAKeyframeAnimation(keyPath: "locations")
        keyframeAnimation.values = [
            [-0.3, -0.2, -0.1, 0.0],
            [1.0, 1.1, 1.2, 1.3],
            [1.0, 1.1, 1.2, 1.3]
        ]
        keyframeAnimation.keyTimes = [0.0, 0.5, 1.0]
        keyframeAnimation.duration = 2
        keyframeAnimation.repeatCount = .infinity

        gradientLayer.add(keyframeAnimation, forKey: "skeletonAnimation")
    }
    
    public func stopAnimating() {
        isAnimating = false
        isHidden = true
        gradientLayer.removeAnimation(forKey: "skeletonAnimation")
    }
    
    public func updateTheme() {
        gradientLayer.colors = [colors[0].cgColor, colors[1].cgColor, colors[1].cgColor, colors[0].cgColor]
    }
    
    public func applyMask(with views: [UIView]) {
        guard let superview else {
            return
        }
        self.mask = createCombinedMask(from: views, in: superview)
    }
    
    private func createCombinedMask(from views: [UIView], in parentView: UIView) -> UIView {
        let maskView = UIView(frame: parentView.bounds)
        maskView.backgroundColor = .clear
        
        for view in views {
            let convertedFrame = parentView.convert(view.frame, from: view.superview)
            let cornerRadius = view.layer.cornerRadius
            let maskedCorners = view.layer.maskedCorners
            
            let maskLayer = CALayer()
            maskLayer.frame = convertedFrame
            maskLayer.cornerRadius = cornerRadius
            maskLayer.maskedCorners = maskedCorners
            maskLayer.backgroundColor = UIColor.white.cgColor
            maskView.layer.addSublayer(maskLayer)
        }
        return maskView
    }
}
