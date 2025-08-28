//
//  EmptyWalletView.swift
//  UIWalletHome
//
//  Created by Sina on 4/21/23.
//

import UIKit
import WalletContext

public class EmptyWalletView: WTouchPassView {
    
    public init() {
        super.init(frame: CGRect.zero)
        setupView()
    }
    
    override public init(frame: CGRect) {
        fatalError()
    }
    
    required public init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    public enum State {
        case empty(address: String)
        case hidden
    }

    private var state: State = .hidden
    public func set(state: State, animated: Bool) {
        self.state = state
        switch state {
        case .empty(let address):
            showWalletCreatedView(address: address, animated: animated)
        case .hidden:
            hide(animated: animated)
        }
    }
    
    // switch from loading/hidden to wallet created animation and wallet address
    private var walletCreatedView: WalletCreatedView? = nil
    private func showWalletCreatedView(address: String, animated: Bool) {
        if walletCreatedView?.alpha ?? 0 > 0 {
            // already showing wallet created view
            return
        }
        
        transform = CGAffineTransform.identity
        alpha = 1

        // created wallet view
        walletCreatedView = WalletCreatedView(address: address)
        walletCreatedView!.alpha = 0
        addSubview(walletCreatedView!)
        NSLayoutConstraint.activate([
            walletCreatedView!.leftAnchor.constraint(equalTo: leftAnchor),
            walletCreatedView!.rightAnchor.constraint(equalTo: rightAnchor),
            walletCreatedView!.topAnchor.constraint(equalTo: topAnchor),
            walletCreatedView!.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])

        if animated {
            layoutIfNeeded()
            UIView.animate(withDuration: 0.4) { [weak self] in
                self?.walletCreatedView!.alpha = 1
            }
        } else {
            walletCreatedView!.alpha = 1
        }
    }
    
    // hide view
    public func hide(animated: Bool) {
        guard animated else {
            self.walletCreatedView?.alpha = 0
            return
        }
        if walletCreatedView?.alpha ?? 0 == 0 {
            // already hidden!
            return
        }
        UIView.animate(withDuration: 0.4, animations: {
            self.transform = CGAffineTransform(translationX: 0, y: 100)
            self.walletCreatedView?.alpha = 0
            self.layoutIfNeeded()
        })
    }
    
}
