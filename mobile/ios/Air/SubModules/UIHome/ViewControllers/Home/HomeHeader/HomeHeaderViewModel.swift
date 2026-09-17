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

enum HomeHeaderState {
    case collapsed
    case expanded
}

@Perceptible @MainActor
final class HomeHeaderViewModel: WalletCoreData.EventsObserver {
    
    let accountSource: AccountSource
    
    var height: CGFloat = 0
    var state: HomeHeaderState = .expanded
    private var cardFadeOpacity: Double = 1
    var _collapseProgress: CGFloat = 0
    var seasonalThemingVersion: Int = 0
    
    var isCollapsed: Bool { state == .collapsed }
    var cardOpacity: Double { isCollapsed ? cardFadeOpacity : 1 }
    var isCardHidden: Bool { cardOpacity == 0 }
    var collapseProgress: CGFloat { isCollapsed ? _collapseProgress : 0 }
    var miniatureCardVerticalOffset: CGFloat {
        rootNavigationStyle.usesNavigationBarTopTabs
            ? -126
            : (IOS_26_MODE_ENABLED ? -124 : -126)
    }
    var seasonalTheme: ApiUpdate.UpdateConfig.SeasonalTheme? {
        _ = seasonalThemingVersion
        guard !AppStorageHelper.isSeasonalThemingDisabled else {
            return nil
        }
        return ConfigStore.shared.config?.seasonalTheme
    }

    let collapsedHeight: CGFloat
    let rootNavigationStyle: HomeRootNavigationStyle
    
    @PerceptionIgnored
    var onSelect: (String) -> () = { _ in }

    @PerceptionIgnored
    var onExpand: () -> Void = {}
    
    @PerceptionIgnored
    @Dependency(\.accountStore.currentAccountId) var currentAccountId
    @PerceptionIgnored
    @Dependency(\.accountStore) var accountStore
    
    init(
        accountSource: AccountSource,
        rootNavigationStyle: HomeRootNavigationStyle = .standard
    ) {
        self.accountSource = accountSource
        self.rootNavigationStyle = rootNavigationStyle
        self.collapsedHeight = rootNavigationStyle.usesNavigationBarTopTabs
            ? 166
            : 95
        WalletCoreData.add(eventObserver: self)
    }
    
    func scrollOffsetChanged(to y: CGFloat) {
        let p = y / collapsedHeight
        _collapseProgress = clamp(p, to: 0...1)
    }

    func updateCardVisibility(bottomOffsetFromSafeArea: CGFloat) {
        let fadeDistance: CGFloat = 16
        cardFadeOpacity = UIDevice.current.hasDynamicIsland
            ? Double(clamp(1 + bottomOffsetFromSafeArea / fadeDistance, to: 0...1))
            : 1
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
