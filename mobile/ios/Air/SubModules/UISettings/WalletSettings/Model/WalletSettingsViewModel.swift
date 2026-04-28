//
//  WalletSettingsViewModel.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.11.2025.
//

import UIKit
import WalletContext
import WalletCore
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

@Perceptible
final class WalletSettingsViewModel {
    
    var currentFilter: WalletFilter = .ledger {
        didSet {
            AppStorageHelper.walletSettingsCurrentFilter = currentFilter.rawValue
        }
    }
    
    var preferredLayout: WalletListLayout {
        didSet {
            AppStorageHelper.walletSettingsListLayout = preferredLayout.rawValue
        }
    }
    
    var filters: [WalletFilter] {
        didSet {
            AppStorageHelper.walletSettingsFilterOrder = filters.map { $0.rawValue }
        }
    }
    
    var isReordering: Bool = false
    var segmentedControllerDidSwitchTrigger: Int = 0
    var onStartEditing: (() -> Void)?
    var onStopEditing: ((Bool) -> Void)?

    init() {
        let allFilters = OrderedSet(WalletFilter.allCases)
        let savedFilters = OrderedSet(AppStorageHelper.walletSettingsFilterOrder.compactMap { WalletFilter(rawValue: $0) })
        self.filters = Array(savedFilters.union(allFilters))
        self.currentFilter = .init(rawValue: AppStorageHelper.walletSettingsCurrentFilter) ?? .all
        self.preferredLayout = .init(rawValue: AppStorageHelper.walletSettingsListLayout) ?? .grid
    }
        
    func startEditing() {
        if !isReordering {
            isReordering = true
            onStartEditing?()
        }
    }
    
    func stopEditing(isCanceled: Bool) {
        if isReordering {
            isReordering = false
            onStopEditing?(isCanceled)
        }
    }
}
