//
//  WBlurView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/26/24.
//

import UIKit
import WalletContext

public final class GradientView: UIView {
    public override class var layerClass: AnyClass { CAGradientLayer.self }
    
    public var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }
    
    public var colors: [UIColor] = [] {
        didSet {
            applyColors()
        }
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
    }
    
    private func applyColors() {
        gradientLayer.colors = colors.map(\.cgColor)
    }
}
