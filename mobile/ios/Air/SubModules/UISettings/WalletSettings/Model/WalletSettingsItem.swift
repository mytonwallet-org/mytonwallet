//
//  WalletSettingsItem.swift
//  MyTonWalletAir
//
//  Created by nikstar on 04.11.2025.
//

import UIKit
import WalletCore
import WalletContext
import UIComponents
import SwiftUI
import Dependencies
import Perception
import OrderedCollections


@Perceptible
final class WalletSettingsItemViewModel {
    
    var accountId: String
    var cardProvider: AccountCurrentMtwCardProvider
    
    @PerceptionIgnored
    @Dependency(\.accountStore.accountsById) var accountsById
    @PerceptionIgnored
    @Dependency(\.accountStore.currentAccountId) var currentAccountId
    @PerceptionIgnored
    @Dependency(\.balanceStore.accountBalanceData) var balanceData
    @PerceptionIgnored
    @Dependency(\.tokenStore.baseCurrency) var baseCurrency
    
    init(accountId: String) {
        self.accountId = accountId
        self.cardProvider = AccountCurrentMtwCardProvider(accountId: accountId)
    }
    
    var account: MAccount {
        accountsById[accountId] ?? DUMMY_ACCOUNT
    }
    var isCurrent: Bool {
        account.id == currentAccountId
    }
    var balance: BaseCurrencyAmount? {
        if let totalBalance = balanceData[accountId]?.totalBalance {
            return BaseCurrencyAmount.fromDouble(totalBalance, baseCurrency)
        }
        return nil
    }
}
