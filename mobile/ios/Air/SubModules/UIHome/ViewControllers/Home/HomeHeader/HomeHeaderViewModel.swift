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
    var isVisible = false
    private var cardFadeOpacity: Double = 1
    var _collapseProgress: CGFloat = 0
    var seasonalThemingVersion: Int = 0
    var isAccountScrolling = false
    private(set) var walletCardTopLine: WalletCardTopLine = .defaultValue

    @PerceptionIgnored
    private nonisolated(unsafe) var settingsObservation: NSObjectProtocol?
    
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
        updateSettings()
        // Defaults can change while ConfigStore holds its queue. Never block the
        // posting queue while the main actor reads configuration during rendering.
        settingsObservation = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateSettings() }
        }
        WalletCoreData.add(eventObserver: self)
    }

    func allowsCardEffects(for accountId: String) -> Bool {
        guard isVisible, !isCollapsed, !isCardHidden, !isAccountScrolling else { return false }
        switch accountSource {
        case .current: return accountId == currentAccountId
        case .accountId(let selected): return accountId == selected
        case .constant(let account): return accountId == account.id
        }
    }

    private func updateSettings() {
        let topLine = WalletCardTopLine(rawValue: UserDefaults.standard.string(forKey: WalletCardSettings.topLineUserDefaultsKey) ?? "") ?? .defaultValue
        if walletCardTopLine != topLine { walletCardTopLine = topLine }
    }

    deinit {
        if let settingsObservation { NotificationCenter.default.removeObserver(settingsObservation) }
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
