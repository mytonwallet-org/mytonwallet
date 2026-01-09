//
//  WalletFilter.swift
//  MyTonWalletAir
//
//  Created by nikstar on 10.11.2025.
//

import WalletCore
import WalletContext

enum WalletFilter: String {
    case all
    case my
    case ledger
    case view
}

extension WalletFilter {
    var accountType: AccountType? {
        switch self {
        case .all:
            nil
        case .my:
            .mnemonic
        case .ledger:
            .hardware
        case .view:
            .view
        }
    }
    
    var addTitle: String {
        switch self {
        case .all, .my:
            lang("Add New Wallet")
        case .ledger:
            lang("Add Ledger Wallet")
        case .view:
            lang("Add View Wallet")
        }
    }
    
    @MainActor func performAddAction() {
        switch self {
        case .all, .my:
            AppActions.showAddWallet(showCreateWallet: true, showSwitchToOtherVersion: true)
        case .ledger:
            AppActions.showAddWallet(showCreateWallet: true, showSwitchToOtherVersion: true)
        case .view:
            AppActions.showAddWallet(showCreateWallet: true, showSwitchToOtherVersion: true)
        }
    }
    
    var emptyTitle: String {
        switch self {
        case .all, .my:
            lang("You don’t have any wallets yet")
        case .ledger:
            lang("No Ledger wallets yet")
        case .view:
            lang("No view wallets yet")
        }
    }
    
    var emptySubtitle: String {
        switch self {
        case .all, .my, .ledger:
            lang("Add your first one to begin.")
        case .view:
            lang("Add the first one to track balances and activity for any address.")
        }
    }
}
