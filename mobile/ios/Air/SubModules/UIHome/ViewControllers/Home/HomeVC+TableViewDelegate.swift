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
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if isExpandingProgrammatically, scrollView.contentOffset.y == 0 {
            // return to prevent top bar jump glitch
            return
        }
        contentOffsetChanged()
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView,
                                          withVelocity velocity: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        
        scrollView.contentInset.top = headerViewModel.state == .expanded ? expansionInset : 0
        
        let realTargetY = targetContentOffset.pointee.y + scrollView.contentInset.top - (headerViewModel.state == .expanded ? expansionInset : 0)
        let isTargetCollapsed = headerViewModel.state == .collapsed || realTargetY > collapseOffset
        
        if isTargetCollapsed && realTargetY > 0 && realTargetY < 120 {
            let isGoingDown = targetContentOffset.pointee.y > scrollView.contentOffset.y
            let isStopped = targetContentOffset.pointee.y == scrollView.contentOffset.y
            if headerViewModel.state == .collapsed && (isGoingDown || (isStopped && realTargetY - 52 >= 0)) {
                targetContentOffset.pointee.y = 110 - scrollView.contentInset.top
            } else {
                targetContentOffset.pointee.y = -scrollView.contentInset.top
            }
        } else if !isTargetCollapsed, realTargetY != 0 {
            targetContentOffset.pointee.y = -scrollView.contentInset.top
        }
    }
}
