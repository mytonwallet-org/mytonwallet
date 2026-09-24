//
//  HomeVC+TableViewDelegate.swift
//  UIHome
//
//  Created by Sina on 7/12/24.
//

import Foundation
import UIKit
import UIComponents

extension HomeVC {
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        collectionView.traceHomeGestureBegan()
    }
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        collectionView.countHomeWork("scroll")
        collectionView.flushHomeTrace(reason: "scroll")
        if isExpandingProgrammatically, scrollView.contentOffset.y == 0 {
            // return to prevent top bar jump glitch
            return
        }
        contentOffsetChanged()
        updateVisibleActivityNftAnimationPlayback()
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let proposedTargetY = targetContentOffset.pointee.y
        defer {
            collectionView.traceHome("scroll.snap", "proposedY=\(proposedTargetY) targetY=\(targetContentOffset.pointee.y) velocityY=\(velocity.y) header=\(headerViewModel.state)")
        }
        
        scrollView.contentInset.top = headerViewModel.state == .expanded ? expansionInset : 0

        let minimumContentOffsetY = -scrollView.adjustedContentInset.top
        let maximumContentOffsetY = max(
            minimumContentOffsetY,
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        )

        // Reaching the actual content end takes precedence over header snapping. This is
        // especially important for short Home content, whose bottom can fall inside the
        // collapsed-header snap range (notably with the top-tabs navigation style).
        if headerViewModel.state == .collapsed,
           targetContentOffset.pointee.y >= maximumContentOffsetY - 0.5 {
            targetContentOffset.pointee.y = maximumContentOffsetY
            return
        }
        
        let realTargetY = targetContentOffset.pointee.y + scrollView.adjustedContentInset.top - (headerViewModel.state == .expanded ? expansionInset : 0)
        let isTargetCollapsed = headerViewModel.state == .collapsed || realTargetY > collapseOffset
        
        if isTargetCollapsed && realTargetY > 0 && realTargetY < rootNavigationStyle.collapsedHeaderSnapRange {
            let isGoingDown = targetContentOffset.pointee.y > scrollView.contentOffset.y
            let isStopped = targetContentOffset.pointee.y == scrollView.contentOffset.y
            if headerViewModel.state == .collapsed &&
                (isGoingDown ||
                    (isStopped && realTargetY >= rootNavigationStyle.collapsedHeaderSnapThreshold)) {
                let collapsedTargetY = rootNavigationStyle.collapsedHeaderSnapOffset
                    - scrollView.adjustedContentInset.top
                targetContentOffset.pointee.y = min(collapsedTargetY, maximumContentOffsetY)
            } else {
                targetContentOffset.pointee.y = minimumContentOffsetY
            }
        } else if !isTargetCollapsed, realTargetY != 0 {
            targetContentOffset.pointee.y = minimumContentOffsetY
        }
    }
}
