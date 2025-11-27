//
//  WalletCardView.swift
//  UIHome
//
//  Created by Sina on 7/10/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import SwiftUIIntrospect

private let log = Log("WalletCardView")
internal let defaultGradientRect = CGRect(x: 0, y: 0, width: 220, height: 100)


public class WalletCardView: WTouchPassView {
    
    public static var defaultState: State = .expanded
    public static var expansionOffset = CGFloat(40)
    public static var collapseOffset = CGFloat(10)
    
    private var feedbackGenerator: UIImpactFeedbackGenerator?
    
    init() {
        super.init(frame: .zero)
        setupViews()
        prepareFeedbackGenerator()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func prepareFeedbackGenerator() {
        DispatchQueue.global(qos: .background).async {
            let start = Date()
            let g = UIImpactFeedbackGenerator(style: .soft)
            self.feedbackGenerator = g
            g.prepare()
            log.info("prepare vibrate took \(Date().timeIntervalSince(start)) isMainThread=\(Thread.isMainThread)")
        }
    }
    
    // MARK: - States and Variables
    // Updated from balance header view, on scroll
    func setScrollOffset(to scrollOffset: CGFloat, isTracking: Bool?, forceIsTracking: Bool) {
        if scrollOffset <= -WalletCardView.expansionOffset, state == .collapsed {
            if (!forceIsTracking && isTracking == false) {
                return
            }
            state = .expanded
            feedbackGenerator?.impactOccurred(intensity: 0.75)
        } else if state == .expanded, scrollOffset >= WalletCardView.collapseOffset {
            state = .collapsed
            feedbackGenerator?.impactOccurred(intensity: 0.75)
        }
    }
    public enum State {
        case collapsed
        case expanded
    }
    private(set) var state = defaultState {
        didSet {
            guard state != oldValue else {
                return
            }
            UIView.animate(withDuration: 0.25) {
                self.layoutCardConstraints()
                self.superview?.layoutIfNeeded()
            } completion: { _ in
                self.delayedState = self.state
            }
            UIView.animate(withDuration: 0.1, delay: state == .collapsed ? 0.15 : 0) {
                self.cardBackground.update(state: self.state)
            } completion: { _ in
                self.delayedState = self.state
            }
            UIView.animate(withDuration: 0.25, delay: 0) {
                let scale = (1 / WAnimatedAmountLabelConfig.cardToBalanceHeaderRatio) * 0.85
            }
            
        }
    }
    private(set) var delayedState = defaultState
    var statusViewState: UpdateStatusView.State = .updated {
        didSet {
            updateContentAlpha()
        }
    }
    
    private var balanceTopConstant: CGFloat {
        if let window, window.frame.width > 410 {
            72
        } else {
            62
        }
    }
    
    func layoutCardConstraints() {
//        if let balanceHeaderView {
////            balanceHeaderView.walletCardViewPreferredBottomConstraint.constant = state == .expanded ? 1000 : -28
//            widthConstraint.constant = state == .expanded ? balanceHeaderView.frame.width - 32 : 34
//            balanceTopConstraint.constant = state == .expanded ? balanceTopConstant : 1000
//            layer.cornerRadius = state == .expanded ? S.homeInsetSectionCornerRadius : 3
//            //        superview?.layoutIfNeeded()
//        }
    }
    
    public override func didMoveToSuperview() {
//        if let balanceHeaderView = superview as? BalanceHeaderView {
//            self.balanceHeaderView = balanceHeaderView
//            layoutCardConstraints()
//            
////            NSLayoutConstraint.activate([
////                balanceCopyBlurView.leadingAnchor.constraint(equalTo: balanceHeaderView.balanceViewSkeleton.leadingAnchor),
////                balanceCopyBlurView.trailingAnchor.constraint(equalTo: balanceHeaderView.balanceViewSkeleton.trailingAnchor),
////                balanceCopyBlurView.topAnchor.constraint(equalTo: balanceHeaderView.balanceViewSkeleton.topAnchor),
////                balanceCopyBlurView.bottomAnchor.constraint(equalTo: balanceHeaderView.balanceViewSkeleton.bottomAnchor),
////
////                balanceWithArrow.centerXAnchor.constraint(equalTo: balanceHeaderView.balanceView.centerXAnchor),
////                balanceCopyView.centerYAnchor.constraint(equalTo: balanceHeaderView.balanceView.centerYAnchor),
////                
////                walletChangeBackground.centerXAnchor.constraint(equalTo: balanceHeaderView.walletNameLabelSkeleton.centerXAnchor),
////            ])
//        }
    }
    
    // MARK: - Views
    private var cardBackground = CardBackground()
    
    private var menuContext = MenuContext()
    
    private lazy var contentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(cardBackground)
        
        NSLayoutConstraint.activate([
            cardBackground.topAnchor.constraint(equalTo: v.topAnchor),
            cardBackground.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            cardBackground.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            cardBackground.trailingAnchor.constraint(equalTo: v.trailingAnchor),

        ])
        return v
    }()

    private var widthConstraint: NSLayoutConstraint!
    private var balanceTopConstraint: NSLayoutConstraint!
    
    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.masksToBounds = true
        addSubview(contentView)

        widthConstraint = widthAnchor.constraint(equalToConstant: 34)

        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalTo: widthAnchor, multiplier: CARD_RATIO),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
    
    // MARK: - Update methods
    
    func set(balanceChangeText: String?, animated: Bool = true) {
    }

    func updateWithCurrentNft(accountChanged: Bool) {
    }
    
    private func animateAlpha(to alpha: CGFloat) {
        UIView.animate(withDuration: 0.2, animations: { [weak self] in
            self?.contentView.alpha = alpha
        })
    }

    private var currentAlpha = 1
    private func updateContentAlpha() {
        if state == .collapsed {
            // Card view may be above stateView, so hide it if required
            switch statusViewState {
            case .waitingForNetwork, .updating:
                if currentAlpha == 1 {
                    currentAlpha = 0
                    animateAlpha(to: 0)
                }
            case .updated:
                if currentAlpha == 0 {
                    currentAlpha = 1
                    animateAlpha(to: 1)
                }
            }
        } else {
            if currentAlpha == 0 {
                currentAlpha = 1
                animateAlpha(to: 1)
            }
        }
    }
}
