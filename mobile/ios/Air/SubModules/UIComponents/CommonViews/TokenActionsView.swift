//
//  TokenActionsView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/11/24.
//

import UIKit
import WalletContext

let actionsRowHeight: CGFloat = IOS_26_MODE_ENABLED ? 70 : 60

public class TokenActionsView: WTouchPassStackView {
    
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
        spacing = IOS_26_MODE_ENABLED ? 16 : 8
        distribution = IOS_26_MODE_ENABLED ? .equalSpacing : .fillEqually
        clipsToBounds = false
        if IOS_26_MODE_ENABLED {
            widthAnchor.constraint(equalToConstant: 304).isActive = true
        }
        
        heightConstraint = heightAnchor.constraint(equalToConstant: actionsRowHeight)
        NSLayoutConstraint.activate([
            heightConstraint,
        ])
        
        let addButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Add").lowercased() : lang("Add").lowercased(),
            image: .airBundle(IOS_26_MODE_ENABLED ? "AddIconBold" : "AddIcon"),
            onTap: { [weak self] in self?.delegate.addPressed() },
        )
        addArrangedSubview(addButton)
        
        let sendButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Send") : lang("Send").lowercased(),
            image: .airBundle(IOS_26_MODE_ENABLED ? "SendIconBold" : "SendIcon"),
            onTap: { [weak self] in self?.delegate.sendPressed() },
        )
        addArrangedSubview(sendButton)
        
        swapButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Swap") : lang("Swap").lowercased(),
            image: .airBundle(IOS_26_MODE_ENABLED ? "SwapIconBold" : "SwapIcon"),
            onTap: { [weak self] in self?.delegate.swapPressed() },
        )
        addArrangedSubview(swapButton)
        
        earnButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Earn") : lang("Earn").lowercased(),
            image: .airBundle(IOS_26_MODE_ENABLED ? "EarnIconBold" : "EarnIcon"),
            onTap: { [weak self] in self?.delegate.earnPressed() },
        )
        addArrangedSubview(earnButton)
    }
    
    public func set(actionsVisibleHeight: CGFloat) {
        let actionButtonAlpha = actionsVisibleHeight < actionsRowHeight ? actionsVisibleHeight / actionsRowHeight : 1
        let maxRadius = S.actionButtonCornerRadius
        let actionButtonRadius = min(maxRadius, actionsVisibleHeight / 2)
        for btn in arrangedSubviews {
            guard let btn = btn as? WScalableButton else { continue }
            btn.set(scale: actionButtonAlpha, radius: actionButtonRadius)
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
