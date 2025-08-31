//
//  WScalableButton.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/22/24.
//

import UIKit
import WalletContext

public class WScalableButton: UIView, WThemedView {
    
    private let title: String
    private let image: UIImage?
    private let onTap: (() -> Void)?

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
    
    public private(set) var innerButton: WButton!
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 12
        layer.masksToBounds = true

        innerButton = WButton(style: .accent)
        innerButton.translatesAutoresizingMaskIntoConstraints = false
        innerButton.setTitle(title, for: .normal)
        innerButton.setImage(image, for: .normal)
        innerButton.imageView?.contentMode = .scaleAspectFit
        innerButton.centerTextAndImage(spacing: 5)
        
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
        
        updateTheme()
    }
    
    public func updateTheme() {
        backgroundColor = WTheme.accentButton.background
    }
    
    public func set(scale: CGFloat) {
        innerButton.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
    
    @objc private func buttonTapped() {
        onTap?()
    }

    public func addTarget(_ target: Any?, action: Selector) {
        innerButton.addTarget(target, action: action, for: .touchUpInside)
    }
}
