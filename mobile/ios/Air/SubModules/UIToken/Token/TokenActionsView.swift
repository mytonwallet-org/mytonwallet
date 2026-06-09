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
    static let usesSplitHomeActionStyle = UIDevice.current.userInterfaceIdiom == .pad
    static let rowHeight: CGFloat = usesSplitHomeActionStyle ? WActionTileButton.sideLength : WScalableButton.preferredHeight
    
    private let accountContext: AccountContext
    
    var token: ApiToken?
    
    init(accountContext: AccountContext, token: ApiToken?) {
        self.accountContext = accountContext
        self.token = token
        super.init(frame: .zero)
        setupViews()
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var addButton: UIView!
    private var swapButton: UIView!
    private var earnButton: UIView!
    private var sendButton: UIView!
    private var heightConstraint: NSLayoutConstraint!
    
    private let buttonsToolbar = ButtonsToolbar()

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        spacing = 16
        distribution = .fill
        clipsToBounds = false
        
        heightConstraint = heightAnchor.constraint(equalToConstant: Self.rowHeight)
        NSLayoutConstraint.activate([
            heightConstraint,
        ])
        
        var buttons: [UIView] = []
        
        addButton = makeButton(
            title: lang("Fund"),
            image: .airBundle(Self.usesSplitHomeActionStyle ? "DepositIconLarge" : "AddIconBold"),
            onTap: { [weak self] in self?.addPressed() },
        )
        buttons += addButton
        
        sendButton = makeButton(
            title: lang("Send"),
            image: .airBundle(Self.usesSplitHomeActionStyle ? "SendIconLarge" : "SendIconBold"),
            onTap: { [weak self] in self?.sendPressed() },
        )
        buttons += sendButton

        swapButton = makeButton(
            title: lang("Swap"),
            image: .airBundle(Self.usesSplitHomeActionStyle ? "SwapIconLarge" : "SwapIconBold"),
            onTap: { [weak self] in self?.swapPressed() },
        )
        buttons += swapButton

        earnButton = makeButton(
            title: lang("Earn"),
            image: .airBundle(Self.usesSplitHomeActionStyle ? "EarnIconLarge" : "EarnIconBold"),
            onTap: { [weak self] in self?.earnPressed() },
        )
        buttons += earnButton

        if Self.usesSplitHomeActionStyle {
            for button in buttons {
                addArrangedSubview(button)
            }
        } else {
            buttonsToolbar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(buttonsToolbar)
            NSLayoutConstraint.activate([
                buttonsToolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
                buttonsToolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
                buttonsToolbar.topAnchor.constraint(equalTo: topAnchor), // will be broken when pushed against the top
                buttonsToolbar.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            for button in buttons {
                buttonsToolbar.addArrangedSubview(button)
            }
        }
    }
    
    private func makeButton(title: String, image: UIImage?, onTap: @escaping () -> Void) -> UIView {
        if Self.usesSplitHomeActionStyle {
            let button = WActionTileButton(title: title, image: image, onTap: onTap)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: WActionTileButton.sideLength),
            ])
            return button
        }

        return WScalableButton(title: title, image: image, onTap: onTap)
    }
    
    private func updateSpacing() {
        if Self.usesSplitHomeActionStyle {
            spacing = 16
        } else {
            buttonsToolbar.update()
        }
    }
    
    var fundAvailable: Bool {
        get {
            return !addButton.isHidden
        }
        set {
            addButton.isHidden = !newValue
            updateSpacing()
        }
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
    var sendAvailable: Bool {
        get {
            return !sendButton.isHidden
        }
        set {
            sendButton.isHidden = !newValue
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

    var hasVisibleActions: Bool {
        fundAvailable || sendAvailable || swapAvailable || earnAvailable
    }
    
    func addPressed() {
        AppActions.showReceive(accountContext: accountContext, chain: token?.chain)
    }

    func sendPressed() {
        AppActions.showSend(accountContext: accountContext, prefilledValues: .init(
            token: token?.slug
        ))
    }

    func swapPressed() {
        AppActions.showSwap(
            accountContext: accountContext,
            defaultSellingToken: token?.slug,
            defaultBuyingToken: token?.slug == "toncoin" ? nil : "toncoin",
            defaultSellingAmount: nil,
            push: nil
        )
    }

    func earnPressed() {
        AppActions.showEarn(accountContext: accountContext, tokenSlug: token?.slug)
    }
}
