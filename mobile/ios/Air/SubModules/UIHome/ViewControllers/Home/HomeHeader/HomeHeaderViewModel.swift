//
//  HomeHeaderViewModel.swift
//  MyTonWalletAir
//
//  Created by nikstar on 19.11.2025.
//

import Foundation
import UIKit
import UIComponents
import WalletCore
import WalletContext
import SwiftUI
import Perception
import Dependencies
import SwiftNavigation

private let log = Log("HomeCard")

enum HomeHeaderState {
    case collapsed
    case expanded
}

@Perceptible
final class HomeHeaderViewModel {
    
    let accountSource: AccountSource
    
    var height: CGFloat = 0
    var state: HomeHeaderState = .expanded
    var isCardHidden = false
    var _collapseProgress: CGFloat = 0
    
    var isCollapsed: Bool { state == .collapsed }
    var collapseProgress: CGFloat { isCollapsed ? _collapseProgress : 0 }

    let collapsedHeight: CGFloat = 95
    
    @PerceptionIgnored
    var onSelect: (String) -> () = { _ in }
    
    @PerceptionIgnored
    @Dependency(\.accountStore.currentAccountId) var currentAccountId
    @PerceptionIgnored
    @Dependency(\.accountStore) var accountStore
    
    init(accountSource: AccountSource) {
        self.accountSource = accountSource
    }
    
    func scrollOffsetChanged(to y: CGFloat) {
        let p = y / collapsedHeight
        _collapseProgress = clamp(p, to: 0...1)
        if UIDevice.current.hasDynamicIsland {
            isCardHidden = y > 62
        }
    }
}

