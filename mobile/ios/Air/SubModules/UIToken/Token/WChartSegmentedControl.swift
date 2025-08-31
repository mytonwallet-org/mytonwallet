//
//  CustomSegmentedControl.swift
//  UIComponents
//
//  Created by Sina on 11/1/24.
//

import UIKit
import WalletContext

public class WChartSegmentedControl: UISegmentedControl, WThemedView {
    private let segmentInset: CGFloat = 5
    private var segmentImage: UIImage? = UIImage(color: WTheme.background)

    private var isFirstRender = true
    public override func layoutSubviews(){
        super.layoutSubviews()

        if isFirstRender {
            for i in 0 ... (self.numberOfSegments-1) {
                let bg = self.subviews[i]
                bg.isHidden = true
            }
            isFirstRender = false
        }
        layer.cornerRadius = bounds.height / 2
        updateTheme()
    }
    
    public func updateTheme() {
        segmentImage = UIImage(color: traitCollection.userInterfaceStyle == .dark ? WTheme.thumbBackground : .white)
        backgroundColor = WTheme.balanceHeaderView.background
        let foregroundIndex = numberOfSegments
        if subviews.indices.contains(foregroundIndex), let foregroundImageView = subviews[foregroundIndex] as? UIImageView {
            foregroundImageView.bounds = foregroundImageView.bounds.insetBy(dx: segmentInset, dy: segmentInset)
            foregroundImageView.image = segmentImage
            foregroundImageView.layer.removeAnimation(forKey: "SelectionBounds") // This removes the weird scaling animation!
            foregroundImageView.layer.masksToBounds = true
            foregroundImageView.layer.cornerRadius = foregroundImageView.bounds.height / 2
        }
    }
}

fileprivate extension UIImage{
    convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
        color.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }
}
