//
//  TokenActionsView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/11/24.
//

import UIKit
import WalletContext

public class TokenActionsView: WTouchPassStackView {
    public static let defaultHeight = CGFloat(60)
    
    @MainActor
    public protocol Delegate {
        func addPressed()
        func sendPressed()
        func swapPressed()
        func earnPressed()
    }
    
    private let delegate: Delegate
    public init(delegate: Delegate) {
        self.delegate = delegate
        super.init(frame: .zero)
        setupViews()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var swapButton: WScalableButton!
    private var earnButton: WScalableButton!
    private var heightConstraint: NSLayoutConstraint!
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        spacing = 8
        distribution = .fillEqually
        layer.masksToBounds = true
        
        heightConstraint = heightAnchor.constraint(equalToConstant: TokenActionsView.defaultHeight)
        NSLayoutConstraint.activate([
            heightConstraint,
        ])
        
        let addButton = WScalableButton(title: lang("Add").lowercased(),
                                        image: UIImage(named: "AddIcon",
                                                       in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
                                        onTap: { [weak self] in
            self?.delegate.addPressed()
        })
        addArrangedSubview(addButton)
        
        let sendButton = WScalableButton(title: lang("Send").lowercased(),
                                         image: UIImage(named: "SendIcon",
                                                        in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
                                         onTap: { [weak self] in
            self?.delegate.sendPressed()
        })
        addArrangedSubview(sendButton)
        
        swapButton = WScalableButton(title: lang("Swap").lowercased(),
                                     image: UIImage(named: "SwapIcon",
                                                    in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
                                     onTap: { [weak self] in
            self?.delegate.swapPressed()
        })
        addArrangedSubview(swapButton)
        
        earnButton = WScalableButton(title: lang("Earn").lowercased(),
                                     image: UIImage(named: "EarnIcon",
                                                    in: AirBundle, compatibleWith: nil)?.withRenderingMode(.alwaysTemplate),
                                     onTap: { [weak self] in
            self?.delegate.earnPressed()
        })
        addArrangedSubview(earnButton)
    }
    
    public func set(actionsVisibleHeight: CGFloat) {
        let actionButtonAlpha = actionsVisibleHeight < 60 ? actionsVisibleHeight / 60 : 1
        let actionButtonRadius = actionsVisibleHeight > 24 ? 12 : actionsVisibleHeight / 2
        for btn in arrangedSubviews {
            guard let btn = btn as? WScalableButton else {continue}
            btn.innerButton.titleLabel?.alpha = actionButtonAlpha
            btn.innerButton.imageView?.alpha = actionButtonAlpha
            btn.layer.cornerRadius = actionButtonRadius
            btn.set(scale: actionButtonAlpha)
        }
        heightConstraint.constant = actionsVisibleHeight
    }
    
    public var swapAvailable: Bool {
        get {
            return !swapButton.isHidden
        }
        set {
            swapButton.isHidden = !newValue
        }
    }
    public var earnAvailable: Bool {
        get {
            return !earnButton.isHidden
        }
        set {
            earnButton.isHidden = !newValue
        }
    }
}
