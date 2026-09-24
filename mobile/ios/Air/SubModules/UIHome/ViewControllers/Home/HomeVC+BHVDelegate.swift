//
//  HomeVC+BHVDelegate.swift
//  UIHome
//
//  Created by Sina on 7/12/24.
//

import Foundation
import UIKit
import UIComponents
import WalletContext
import UIAssets
import SwiftUI

extension HomeVC: BalanceHeaderViewDelegate, WalletAssetsDelegate {
    public func headerIsAnimating() {
        collectionView.traceHome("header.animate", "state=\(headerViewModel.state) programmatic=\(isExpandingProgrammatically)")
        let duration = isExpandingProgrammatically ? 0.2 : 0.3
        UIView.animateAdaptive(duration: duration) { [self] in
            updateTableViewHeaderFrame(animated: true)
            // reset status view to show wallet name in expanded mode and hide in collpased mode
            balanceHeaderView.update(status: balanceHeaderView.updateStatusView.state,
                                     animatedWithDuration: duration)
        } completion: { [weak self] _ in
            guard let self else { return }
            scrollViewDidScroll(collectionView)
        }
    }

    public func walletAssetDidChangeHeight(animated: Bool) {
        guard !isCommittingAccount else { return }
        collectionView.traceHome("assets.heightChanged", "animated=\(animated)")
        updateTableViewHeaderFrame(animated: animated)
        view.setNeedsLayout()
    }

    public func walletAssetDidChangeDisplayTabs(animated: Bool) {
        guard !isCommittingAccount else { return }
        collectionView.traceHome("assets.tabsChanged", "animated=\(animated)")
        applySnapshot(makeSnapshot(reconfiguringCustomSections: [assetsCustomSectionID]), animatingDifferences: animated)
        walletAssetDidChangeHeight(animated: animated)
    }
    
    public func expandHeader() {
        collectionView.traceHome("header.expandProgrammatically")
        isExpandingProgrammatically = true
        headerViewModel.state = .expanded
        collectionView.contentInset.top = expansionInset
        UIView.animate(withDuration: 0.2) { [weak self] in
            guard let self else { return }
            collectionView.contentOffset = .init(x: 0, y: -collectionView.adjustedContentInset.top)
            scrollViewDidScroll(collectionView)
        } completion: { [weak self] _ in
            guard let self else { return }
            collectionView.contentOffset = .init(x: 0, y: -collectionView.adjustedContentInset.top)
            scrollViewDidScroll(collectionView)
            isExpandingProgrammatically = false
        }
    }

    public var isTracking: Bool {
        return collectionView.isTracking
    }
}
