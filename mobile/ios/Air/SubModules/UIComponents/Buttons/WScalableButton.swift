//
//  WScalableButton.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/22/24.
//

import UIKit
import WalletContext

public class WScalableButton: UIView {
    
    private let title: String
    private let image: UIImage?
    public var onTap: (() -> Void)?

    public init(title: String, image: UIImage?, onTap: (() -> Void)?) {
        self.title = title
        self.image = image
        self.onTap = onTap
        super.init(frame: .zero)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public private(set) var innerButton: UIControl!
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = S.actionButtonCornerRadius
        layer.masksToBounds = !IOS_26_MODE_ENABLED

        if #available(iOS 26, iOSApplicationExtension 26, *) {
            let innerButton = GlassActionButton(title: title, image: image, action: { [weak self] in self?.onTap?() })
            self.innerButton = innerButton
        } else {
            let innerButton = WButton(style: .accent)
            self.innerButton = innerButton
            innerButton.translatesAutoresizingMaskIntoConstraints = false
            innerButton.setTitle(title, for: .normal)
            innerButton.setImage(image, for: .normal)
            innerButton.imageView?.contentMode = .scaleAspectFit
            innerButton.centerTextAndImage(spacing: 5)
        }
        
        addSubview(innerButton)
        NSLayoutConstraint.activate([
            innerButton.topAnchor.constraint(equalTo: topAnchor),
            innerButton.leftAnchor.constraint(equalTo: leftAnchor),
            innerButton.rightAnchor.constraint(equalTo: rightAnchor),
            innerButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        
        if onTap != nil {
            innerButton.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        }
        
        backgroundColor = IOS_26_MODE_ENABLED ? .clear : WTheme.accentButton.background
    }
    
    
    public func set(scale: CGFloat, radius: CGFloat) {
        if #available(iOS 26, iOSApplicationExtension 26, *), let innerButton = innerButton as? GlassActionButton {
            innerButton.alpha = scale
            innerButton.transform = CGAffineTransform(scaleX: scale, y: scale)
        } else if let innerButton = innerButton as? WButton {
            innerButton.titleLabel?.alpha = scale
            innerButton.imageView?.alpha = scale
            layer.cornerRadius = radius
            innerButton.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }
    
    @objc private func buttonTapped() {
        onTap?()
    }
}
