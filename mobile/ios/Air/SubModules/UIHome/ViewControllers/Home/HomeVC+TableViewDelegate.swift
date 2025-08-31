//
//  HomeVC+TableViewDelegate.swift
//  UIHome
//
//  Created by Sina on 7/12/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore

extension HomeVC {
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isExpandingProgrammatically, scrollView.contentOffset.y == 0 {
            // return to prevent top bar jump glitch
            return
        }
        contentOffsetChanged(to: scrollView.contentOffset.y + scrollExtraOffset + tableView.contentInset.top)
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let realTargetY = targetContentOffset.pointee.y + scrollView.contentInset.top
        let isTargetCollapsed = balanceHeaderView.walletCardView.state == .collapsed || realTargetY > WalletCardView.collapseOffset
        if isTargetCollapsed && realTargetY > 0 && realTargetY < 120 {
            let isGoingDown = targetContentOffset.pointee.y > scrollView.contentOffset.y
            let isStopped = targetContentOffset.pointee.y == scrollView.contentOffset.y
            if balanceHeaderView.walletCardView.delayedState == .collapsed &&
                (isGoingDown || (isStopped && realTargetY - 52 >= 0)) {
                targetContentOffset.pointee.y = 110 - scrollView.contentInset.top
            } else {
                targetContentOffset.pointee.y = -scrollView.contentInset.top
            }
        } else if !isTargetCollapsed, realTargetY != 0 {
            targetContentOffset.pointee.y = -scrollView.contentInset.top
        }
    }
    
    public override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if scrollExtraOffset != 0 {
            tableView.contentInset.top += scrollExtraOffset
            scrollExtraOffset = 0
        }
        if !decelerate {
            resetScrollIfRequired()
        }
        super.scrollViewDidEndDragging(scrollView, willDecelerate: decelerate)
    }
    
    public override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        // Reset everything
        resetScrollIfRequired()
        super.scrollViewDidEndDecelerating(scrollView)
    }
    
    private func resetScrollIfRequired() {
        if scrollExtraOffset == 0, tableView.contentInset.top != 0 {
            // scroll offset reset done! so reset inset to 0!
            let top = tableView.contentInset.top
            tableView.contentInset.top = 0
            // Check if header is visible, and prevent jump glitch.
            if tableView.contentOffset.y > 0, tableView.visibleCells.contains(where: { cell in
                cell.tag == 123
            }) {
                tableView.contentOffset.y += top
            }
            UIView.performWithoutAnimation {
                actionsTopConstraint.constant = headerHeightWithoutAssets
                self.applySnapshot(self.makeSnapshot(), animated: false)
                tableView.layoutIfNeeded()
            }
        }
    }
}
