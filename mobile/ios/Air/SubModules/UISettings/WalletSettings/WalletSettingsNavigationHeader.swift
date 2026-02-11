//
//  WalletSettingsVC.swift
//  UISettings
//
//  Created by nikstar on 02.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections
import UIKitNavigation

struct WalletSettingsNavigationHeader: View {
    
    let viewModel: WalletSettingsViewModel
    
    @Dependency(\.accountStore.accountsById.values) var accounts
    @Dependency(\.balanceStore) var balanceStore
    
    var body: some View {
        WithPerceptionTracking {
            NavigationHeader {
                Text(lang("$wallets_amount", arg1: count))
                    .fixedSize()
            } subtitle: {
                Text(lang("$total_balance", arg1: total.formatted(.baseCurrencyEquivalent)))
                    .fixedSize()
                    .id(viewModel.currentFilter)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .sensitiveData(
                        alignment: .center,
                        cols: 12,
                        rows: 2,
                        cellSize: nil,
                        theme: .adaptive,
                        cornerRadius: 4
                    )
            }
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.3), value: count)
            .animation(.smooth(duration: 0.3), value: total)
        }
    }
    
    var count: Int {
        let accountType = viewModel.currentFilter.accountType
        var accounts = Array(accounts)
        if let accountType {
            accounts = accounts.filter { $0.type == accountType }
        }
        return accounts.count
    }
    
    var total: BaseCurrencyAmount {
        let filter = viewModel.currentFilter
        let type = filter.accountType
        return balanceStore.totalBalance(ofWalletsWithType: type)
    }
}
