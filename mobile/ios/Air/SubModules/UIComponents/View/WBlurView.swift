//
//  WBlurView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/26/24.
//

import UIKit
import WalletContext

public class WBlurView: UIVisualEffectView, WThemedView {
    
    public static func attach(to view: UIView, style: UIBlurEffect.Style = .light, background: UIColor = WColors.blurBackground) -> WBlurView {
        let v = WBlurView(style: style, background: background)
        view.insertSubview(v, at: 0)
        NSLayoutConstraint.activate([
            v.leftAnchor.constraint(equalTo: view.leftAnchor),
            v.rightAnchor.constraint(equalTo: view.rightAnchor),
            v.topAnchor.constraint(equalTo: view.topAnchor),
            v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return v
    }
    
    private var _backgroundColor: UIColor? = nil
    private let enableSaturation = true
    
    public init(style: UIBlurEffect.Style = .light, background: UIColor = WColors.blurBackground) {
        super.init(effect: UIBlurEffect(style: style))
        translatesAutoresizingMaskIntoConstraints = false
        self._backgroundColor = background
        updateTheme()
        hideExtraLayers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateTheme() {
        backgroundColor = _backgroundColor ?? WColors.blurBackground
    }
    
    public func updateEffect(style: UIBlurEffect.Style) {
        effect = UIBlurEffect(style: style)
        hideExtraLayers()
    }
    
    private func hideExtraLayers() {
        for subview in subviews {
            if subview.description.contains("VisualEffectSubview") {
                subview.isHidden = true
            }
        }
        
        if let sublayer = layer.sublayers?[0], let filters = sublayer.filters {
            sublayer.backgroundColor = nil
            sublayer.isOpaque = false
            var allowedKeys: [String] = [
                "gaussianBlur"
            ]
            if self.enableSaturation {
                allowedKeys.append("colorSaturate")
            }
            sublayer.filters = filters.filter { filter in
                guard let filter = filter as? NSObject else {
                    return true
                }
                let filterName = String(describing: filter)
                if !allowedKeys.contains(filterName) {
                    return false
                }
                return true
            }
        }
    }
}
