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
final class HomeHeaderViewModel: WalletCoreData.EventsObserver {
    
    let accountSource: AccountSource
    
    var height: CGFloat = 0
    var state: HomeHeaderState = .expanded
    var isCardHidden = false
    var _collapseProgress: CGFloat = 0
    var seasonalThemingVersion: Int = 0
    
    var isCollapsed: Bool { state == .collapsed }
    var collapseProgress: CGFloat { isCollapsed ? _collapseProgress : 0 }
    var seasonalTheme: ApiUpdate.UpdateConfig.SeasonalTheme? {
        _ = seasonalThemingVersion
        guard !AppStorageHelper.isSeasonalThemingDisabled else {
            return nil
        }
        return ConfigStore.shared.config?.seasonalTheme
    }

    let collapsedHeight: CGFloat = 95
    
    @PerceptionIgnored
    var onSelect: (String) -> () = { _ in }
    
    @PerceptionIgnored
    @Dependency(\.accountStore.currentAccountId) var currentAccountId
    @PerceptionIgnored
    @Dependency(\.accountStore) var accountStore
    
    init(accountSource: AccountSource) {
        self.accountSource = accountSource
        WalletCoreData.add(eventObserver: self)
    }
    
    func scrollOffsetChanged(to y: CGFloat) {
        let p = y / collapsedHeight
        _collapseProgress = clamp(p, to: 0...1)
        if UIDevice.current.hasDynamicIsland {
            isCardHidden = y > 62
        }
    }

    @MainActor
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .configChanged:
            seasonalThemingVersion += 1
        default:
            break
        }
    }
}
