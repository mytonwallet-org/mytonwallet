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
import SwiftUI

extension HomeVC: BalanceHeaderViewDelegate, WalletAssetsDelegate {
    
    public func headerIsAnimating() {
        if !isExpandingProgrammatically {
//            if balanceHeaderView.walletCardView.state == .expanded {
//                scrollExtraOffset += WalletCardView.expansionOffset
//            } else {
//                scrollExtraOffset -= WalletCardView.collapseOffset
//            }
        }

        let duration = isExpandingProgrammatically ? 0.2 : 0.3
        UIView.animateAdaptive(duration: duration) { [self] in
            withAnimation(.interactiveSpring(duration: 0.3)) {
                updateTableViewHeaderFrame(animated: true)
                // reset status view to show wallet name in expanded mode and hide in collpased mode
                balanceHeaderView.update(status: balanceHeaderView.updateStatusView.state,
                                         animatedWithDuration: duration)
                headerViewModel.state = balanceHeaderView.walletCardView.state
            }
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
