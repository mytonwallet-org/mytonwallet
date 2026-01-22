//
//  TokenActionsView.swift
//  MyTonWalletAir
//
//  Created by Sina on 11/11/24.
//

import UIKit
import UIComponents
import WalletContext
import WalletCore

class TokenActionsView: WTouchPassStackView {
    
    var token: ApiToken?
    
    init(token: ApiToken?) {
        self.token = token
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
        spacing = S.actionButtonSpacing(forButtonCount: 4)
        distribution = IOS_26_MODE_ENABLED ? .equalSpacing : .fillEqually
        clipsToBounds = false
        
        heightConstraint = heightAnchor.constraint(equalToConstant: actionsRowHeight)
        NSLayoutConstraint.activate([
            heightConstraint,
        ])
        
        let addButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Add / Buy") : lang("Add").lowercased(),
            image: .airBundle(IOS_26_MODE_ENABLED ? "AddIconBold" : "AddIcon"),
            onTap: { [weak self] in self?.addPressed() },
        )
        addArrangedSubview(addButton)
        
        let sendButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Send") : lang("Send").lowercased(),
            image: .airBundle(IOS_26_MODE_ENABLED ? "SendIconBold" : "SendIcon"),
            onTap: { [weak self] in self?.sendPressed() },
        )
        addArrangedSubview(sendButton)
        
        swapButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Swap") : lang("Swap").lowercased(),
            image: .airBundle(IOS_26_MODE_ENABLED ? "SwapIconBold" : "SwapIcon"),
            onTap: { [weak self] in self?.swapPressed() },
        )
        addArrangedSubview(swapButton)
        
        earnButton = WScalableButton(
            title: IOS_26_MODE_ENABLED ? lang("Earn") : lang("Earn").lowercased(),
            image: .airBundle(IOS_26_MODE_ENABLED ? "EarnIconBold" : "EarnIcon"),
            onTap: { [weak self] in self?.earnPressed() },
        )
        addArrangedSubview(earnButton)
    }
    
    private func updateSpacing() {
        let visibleCount = arrangedSubviews.filter { !$0.isHidden }.count
        spacing = S.actionButtonSpacing(forButtonCount: visibleCount)
    }
    
    func set(actionsVisibleHeight: CGFloat) {
        let actionButtonAlpha = actionsVisibleHeight < actionsRowHeight ? actionsVisibleHeight / actionsRowHeight : 1
        let maxRadius = S.actionButtonCornerRadius
        let actionButtonRadius = min(maxRadius, actionsVisibleHeight / 2)
        for btn in arrangedSubviews {
            guard let btn = btn as? WScalableButton else { continue }
            btn.set(scale: actionButtonAlpha, radius: actionButtonRadius)
        }
        heightConstraint.constant = actionsVisibleHeight
    }
    
    var swapAvailable: Bool {
        get {
            return !swapButton.isHidden
        }
        set {
            swapButton.isHidden = !newValue
            updateSpacing()
        }
    }
    var earnAvailable: Bool {
        get {
            return !earnButton.isHidden
        }
        set {
            earnButton.isHidden = !newValue
            updateSpacing()
        }
    }
    
    func addPressed() {
        AppActions.showReceive(chain: token?.chainValue, title: nil)
    }

    func sendPressed() {
        AppActions.showSend(prefilledValues: .init(
            token: token?.slug
        ))
    }

    func swapPressed() {
        AppActions.showSwap(
            defaultSellingToken: token?.slug,
            defaultBuyingToken: token?.slug == "toncoin" ? nil : "toncoin",
            defaultSellingAmount: nil,
            push: nil
        )
    }

    func earnPressed() {
        AppActions.showEarn(tokenSlug: token?.slug)
    }
}
