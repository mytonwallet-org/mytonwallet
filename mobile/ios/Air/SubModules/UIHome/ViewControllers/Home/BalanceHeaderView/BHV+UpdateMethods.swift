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

            updateStatusViewContainer.alpha = walletCardView.state == .expanded ? 1 : 0
        }

        if shouldAnimate {
            UIView.animateAdaptive(duration: isExpandingProgrammatically ? 0.2 : 0.3) {
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
        let shouldAnimate = (animated && (!isShowingSkeleton || isShowingSkeletonCompletely)) ? nil : false
        onCompletion?()
    }

    func update(status: UpdateStatusView.State, animatedWithDuration: TimeInterval?) {
        log.info("newStatus=\(status, .public) animated=\(animatedWithDuration as Any, .public)", fileOnly: true)
        updateStatusView.setState(newState: status, animatedWithDuration: animatedWithDuration)
        walletCardView.statusViewState = status
        updateStatusViewContainer.alpha = walletCardView.state == .expanded ? 1 : 0
    }
}
