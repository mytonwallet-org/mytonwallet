//
//  BHV+UpdateMethods.swift
//  UIHome
//
//  Created by Sina on 7/10/24.
//

import Foundation
import UIKit
import UIComponents
import WalletContext

private let log = Log("BalanceHeaderView+update")

private let throttleDuration = 0.03

@MainActor extension BalanceHeaderView {
    
    func updateHeight(scrollOffset: CGFloat, isExpandingProgrammatically: Bool) {

        // detect collapse/expand mode first of all
        if scrollOffset <= -expansionOffset, headerViewModel.state == .collapsed {
            if (!isExpandingProgrammatically && delegate?.isTracking == false) {
                return
            }
            let now = Date()
            if now.timeIntervalSince(lastStateChange) > throttleDuration {
                lastStateChange = now
                headerViewModel.state = .expanded
                Haptics.play(.transition)
            }
        } else if headerViewModel.state == .expanded, scrollOffset >= collapseOffset {
            let now = Date()
            if now.timeIntervalSince(lastStateChange) > throttleDuration {
                lastStateChange = now
                headerViewModel.state = .collapsed
                Haptics.play(.transition)
            }
        }

        var newHeight = calculatedHeight - (isExpandingProgrammatically ? 0 : scrollOffset)

        var shouldAnimate = false
        if prevWalletCardViewState != headerViewModel.state {
            prevWalletCardViewState = headerViewModel.state
            shouldAnimate = true
            // Mode changed, animate considering the offset!
            if !isExpandingProgrammatically {
                newHeight += headerViewModel.state == .expanded ? -expansionOffset : collapseOffset
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

            updateStatusViewContainer.alpha = headerViewModel.state == .expanded ? 1 : 0
        }

        if shouldAnimate {
            UIView.animateAdaptive(duration: isExpandingProgrammatically ? 0.2 : 0.3) {
                updateView()
            }
            delegate?.headerIsAnimating()
        } else {
            updateView()
        }
    }
    
    func update(status: UpdateStatusView.State, animatedWithDuration: TimeInterval?) {
        updateStatusView.setState(newState: status, animatedWithDuration: animatedWithDuration)
        updateStatusViewContainer.alpha = headerViewModel.state == .expanded ? 1 : 0
    }
}
