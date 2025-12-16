//
//  ReversedCornerRadiusView.swift
//  UIComponents
//
//  Created by Sina on 5/4/23.
//

import UIKit
import WalletContext

public class ReversedCornerRadiusView: UIView {
    
    public static let defaultRadius = S.homeInsetSectionCornerRadius
    public var radius: CGFloat = defaultRadius {
        didSet {
            if oldValue == radius {
                return
            }
            updateCornerRadius()
        }
    }
    
    private var borderLayer: CAShapeLayer? = nil
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        updateCornerRadius()
    }
    
    private func updateCornerRadius() {
        // reversed corner radius on bottom
        let width = frame.width
        let rectShape = CAShapeLayer()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: radius + 1, y: 0.33))
        path.addArc(withCenter: CGPoint(x: radius, y: radius + 0.33),
                    radius: radius,
                    startAngle: .pi * 3 / 2,
                    endAngle: .pi,
                    clockwise: false)
        path.addLine(to: CGPoint(x: 0, y: radius + 0.33))
        path.addLine(to: CGPoint(x: 0, y: ReversedCornerRadiusView.defaultRadius))
        path.addLine(to: CGPoint(x: width, y: ReversedCornerRadiusView.defaultRadius))
        path.addLine(to: CGPoint(x: width, y: radius + 0.33))
        path.addLine(to: CGPoint(x: width - 1, y: radius + 0.33))
        path.addArc(withCenter: CGPoint(x: width - radius, y: radius + 0.33),
                    radius: radius,
                    startAngle: 0,
                    endAngle: .pi * 3 / 2,
                    clockwise: false)
        path.addLine(to: CGPoint(x: radius + 1, y: 0.33))
        path.close()
        
        let p = CGMutablePath()
        p.addRect(bounds)
        p.addPath(path.cgPath)
        rectShape.path = p
        layer.mask = rectShape

        // Create the border layer
        borderLayer?.removeFromSuperlayer()
        borderLayer = CAShapeLayer()
        borderLayer!.path = path.cgPath
        borderLayer!.fillColor = UIColor.clear.cgColor
        
        borderLayer!.strokeColor = WTheme.separator.withAlphaComponent((traitCollection.userInterfaceStyle == .dark ? 1 : 0.2) * (1 - (radius / ReversedCornerRadiusView.defaultRadius))).cgColor
        borderLayer!.lineWidth = 1
        layer.addSublayer(borderLayer!)
        layer.masksToBounds = true
    }
}
