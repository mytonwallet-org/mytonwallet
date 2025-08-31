//
//  HomeVC+BHVDelegate.swift
//  UIHome
//
//  Created by Sina on 7/12/24.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import UIAssets


extension HomeVC: BalanceHeaderViewDelegate, WalletAssetsDelegate {
    
    public func headerIsAnimating() {
        if !isExpandingProgrammatically {
            if balanceHeaderView.walletCardView.state == .expanded {
                scrollExtraOffset += WalletCardView.expansionOffset
            } else {
                scrollExtraOffset -= WalletCardView.collapseOffset
            }
        }
        UIView.animate(withDuration: isExpandingProgrammatically ? 0.2 : 0.3, delay: 0, options: .allowUserInteraction) { [self] in
            view.layoutIfNeeded()
            self.updateTableViewHeaderFrame()
            // reset status view to show wallet name in expanded mode and hide in collpased mode
            self.balanceHeaderView.update(status: self.balanceHeaderView.updateStatusView.state,
                                           animatedWithDuration: self.isExpandingProgrammatically ? 0.2 : 0.3)
        } completion: { [weak self] _ in
            guard let self else { return }
            scrollViewDidScroll(tableView)
        }
    }

    public func headerHeightChanged(animated: Bool) {
        updateTableViewHeaderFrame(animated: animated)
        view.setNeedsLayout()
    }

    public func expandHeader() {
        isExpandingProgrammatically = true
        UIView.animate(withDuration: 0.2) { [weak self] in
            guard let self else {return}
            tableView.contentOffset = .init(x: 0, y: -40)
        } completion: { [weak self] _ in
            guard let self else {return}
            isExpandingProgrammatically = false
        }
    }

    public var isTracking: Bool {
        return tableView.isTracking
    }
}
