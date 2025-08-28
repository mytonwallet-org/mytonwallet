//
//  BHV+UpdateMethods.swift
//  UIHome
//
//  Created by Sina on 7/10/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext

private let log = Log("BalanceHeaderView+update")

@MainActor extension BalanceHeaderView {
    
    func updateHeight(scrollOffset: CGFloat, isExpandingProgrammatically: Bool) -> CGFloat {
        if UIDevice.current.hasDynamicIsland {
            if scrollOffset >= 87 {
                self.walletCardView.alpha = 0
            } else {
                walletCardView.alpha = 1
            }
        }

        // Should set wallet card offset first, to detect collapse/expand mode first of all.
        walletCardView.setScrollOffset(to: scrollOffset, isTracking: delegate?.isTracking, forceIsTracking: isExpandingProgrammatically)

        var newHeight = calculatedHeight - (isExpandingProgrammatically ? 0 : scrollOffset)

        var shouldAnimate = false
        if prevWalletCardViewState != walletCardView.state {
            prevWalletCardViewState = walletCardView.state
            shouldAnimate = true
            // Mode changed, animate considering the offset!
            if !isExpandingProgrammatically {
                newHeight += walletCardView.state == .expanded ? -WalletCardView.expansionOffset : WalletCardView.collapseOffset
            }
        }
        if isExpandingProgrammatically {
            shouldAnimate = true
        }

        let updateView = { [self] in
            // balance header view can not be smaller than 44pt
            if newHeight < BalanceHeaderView.minHeight {
                newHeight = BalanceHeaderView.minHeight
            }

            // set the new constraint
            heightConstraint.constant = newHeight

            // progress is between 0 (collapsed) and 1 (expanded)
            let progress: CGFloat = scrollOffset <= 0 ? 1 : (max(0, 110 - scrollOffset) / 110)
            var balanceScale = interpolate(from: 17.0/WAnimatedAmountLabelConfig.balanceHeader.primaryFont.pointSize, to: 1, progress: progress)
            if walletCardView.state == .expanded {
                balanceScale *= WAnimatedAmountLabelConfig.cardToBalanceHeaderRatio
            }
            // set balance view size
            balanceTopConstraint.constant = -2 + progress * 54
            balanceView.update(scale: balanceScale)
            balanceViewSkeleton.transform = CGAffineTransform(scaleX: balanceScale, y: balanceScale)
            balanceContainer.shyMask?.transform = CGAffineTransform(scaleX: balanceScale, y: balanceScale)
            
            walletNameBelowBalanceConstraint.constant = walletCardView.state == .expanded || scrollOffset <= 0 ? 8 : interpolate(from: -3.333, to: 8, progress: progress)
            
            // prevent balance from showing behind card
            balanceView.clipsToBounds = walletCardView.state == .expanded

            // set wallet name scale
            let walletNameScale = interpolate(from: 13.0/17.0, to: 1.0, progress: progress)
            walletNameLabel.transform = CGAffineTransform(scaleX: walletNameScale, y: walletNameScale)
            let walletNameSkeletonScale = walletNameScale * walletNameScale
            walletNameLabelSkeleton.transform = CGAffineTransform(scaleX: walletNameSkeletonScale, y: walletNameSkeletonScale)

            if updateStatusView.state == .updated {
                updateStatusViewContainer.alpha = walletCardView.state == .expanded ? 1 : 0
            } else {
                let progress: CGFloat = min(1, max(0, 2 * progress - 1))
                updateStatusViewContainer.alpha = progress
            }
        }

        if shouldAnimate {
            UIView.animate(withDuration: isExpandingProgrammatically ? 0.2 : 0.3, delay: 0, options: .allowUserInteraction) {
                updateView()
            }
            delegate?.headerIsAnimating()
        } else {
            updateView()
        }

        return newHeight
    }
    
    func update(balance: Double?,
                balance24h: Double?,
                animated: Bool,
                onCompletion: (() -> Void)?) {
        updateWalletName()
        let shouldAnimate = (animated && (!isShowingSkeleton || isShowingSkeletonCompletely)) ? nil : false
        balanceView.set(balanceInBaseCurrency: balance, baseCurrency: TokenStore.baseCurrency, animated: shouldAnimate)
        walletCardView.balanceCopyView.set(balanceInBaseCurrency: balance, baseCurrency: TokenStore.baseCurrency, animated: shouldAnimate)
        if let balance, let balance24h {
            if balance == 0 && balance24h == 0 {
                walletCardView.set(balanceChangeText: "", animated: !isShowingSkeleton || isShowingSkeletonCompletely)
            } else {
                let balanceChangeValueString = formatBigIntText(doubleToBigInt(balance - balance24h,
                                                                             decimals: TokenStore.baseCurrency?.decimalsCount ?? 2),
                                                               currency: TokenStore.baseCurrency?.sign,
                                                               tokenDecimals: TokenStore.baseCurrency?.decimalsCount ?? 9,
                                                               decimalsCount: TokenStore.baseCurrency?.decimalsCount)
                let balanceChangePercentString = balance24h == 0 ? "" : "\(balance - balance24h >= 0 ? "+" : "")\(((balance - balance24h) / balance24h * 10000).rounded() / 100)% · "
                walletCardView.set(balanceChangeText: "\(balanceChangePercentString)\(balanceChangeValueString)", animated: !isShowingSkeleton || isShowingSkeletonCompletely)
            }
        } else {
            walletCardView.set(balanceChangeText: nil, animated: !isShowingSkeleton || isShowingSkeletonCompletely)
        }
        onCompletion?()
        if isShowingSkeleton, balance != nil {
            isShowingSkeleton = false
            isShowingSkeletonCompletely = false
            UIView.animate(withDuration: 0.1) { [weak self] in
                self?.walletNameLabelSkeleton.alpha = 0
                self?.balanceViewSkeleton.alpha = 0
                self?.walletCardView.balanceCopyBlurView.alpha = 0
                self?.walletCardView.walletChangeBackground.layer.cornerRadius = 13
            } completion: { _ in
                guard !self.isShowingSkeleton else {return}
                UIView.animate(withDuration: 0.2) { [weak self] in
                    self?.walletNameLabel.alpha = 1
                    self?.balanceView.alpha = 1
                    self?.walletCardView.balanceWithArrow.alpha = 1
                }
            }
        } else if !isShowingSkeleton, balance == nil {
            isShowingSkeleton = true
            // Wait 0.2 before considering skeletons shown!
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                if isShowingSkeleton {
                    isShowingSkeletonCompletely = true
                }
            }
            // UIView.animate(withDuration: walletNameLabel.alpha > 0 && !(walletNameLabel.text?.isEmpty ?? true) ? 0.5 : 0) { [weak self] in
            UIView.performWithoutAnimation { [weak self] in
                self?.balanceView.alpha = 0
                self?.walletNameLabel.alpha = 0
                self?.walletNameLabelSkeleton.alpha = 1
                self?.balanceViewSkeleton.alpha = 1
                self?.walletCardView.balanceWithArrow.alpha = 0
                self?.walletCardView.balanceCopyBlurView.alpha = 1
                self?.walletCardView.walletChangeBackground.layer.cornerRadius = 8
            }/* completion: { _ in
                guard self.isShowingSkeleton else {return} // balance already changed!
                UIView.animate(withDuration: 0.3) { [weak self] in
                    self?.walletNameLabelSkeleton.alpha = 1
                    self?.balanceViewSkeleton.alpha = 1
                }
            }*/
        }
    }

    func update(status: UpdateStatusView.State, animatedWithDuration: TimeInterval?) {
        log.info("newStatus=\(status, .public) animated=\(animatedWithDuration as Any, .public)", fileOnly: true)
        updateStatusView.setState(newState: status, animatedWithDuration: animatedWithDuration)
        walletCardView.statusViewState = status
        if updateStatusView.state == .updated {
            updateStatusViewContainer.alpha = walletCardView.state == .expanded ? 1 : 0
        } else {
            let progress: CGFloat = min(1, max(0, 4 * (balanceView.scale - 0.75)))
            updateStatusViewContainer.alpha = progress
        }
    }

    func updateWalletName() {
        walletNameLabel.attributedText = NSAttributedString(string: AccountStore.account?.displayName ?? "", attributes: [
            .font: walletNameLabel.font!,
            .foregroundColor: WTheme.secondaryLabel,
            .kern: 0.39
        ])
    }
}
