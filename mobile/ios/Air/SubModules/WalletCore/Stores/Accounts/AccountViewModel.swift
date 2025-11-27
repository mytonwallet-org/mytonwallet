

import UIKit
import SwiftUI
import WalletContext
import Perception
import Dependencies

@Perceptible
public class AccountViewModel {
    
    public var accountId: String
    
    @PerceptionIgnored
    @Dependency(\.accountStore) private var accountStore
    @PerceptionIgnored
    @Dependency(\.accountSettings) private var accountSettings
    @PerceptionIgnored
    @Dependency(\.nftStore) private var nftStore
    @PerceptionIgnored
    @Dependency(\.balanceStore.accountBalanceData) private var balanceData
    @PerceptionIgnored
    @Dependency(\.tokenStore.baseCurrency) private var baseCurrency
    
    public init(accountId: String) {
        self.accountId = accountId
    }
    
    public var account: MAccount {
        accountStore.accountsById[accountId] ?? DUMMY_ACCOUNT
    }
    public var isCurrent: Bool {
        account.id == accountStore.currentAccountId
    }
    public var balance: BaseCurrencyAmount? {
        if let totalBalance = balanceData[accountId]?.totalBalance {
            return BaseCurrencyAmount.fromDouble(totalBalance, baseCurrency)
        }
        return nil
    }
    public var balance24h: BaseCurrencyAmount? {
        if let totalBalance = balanceData[accountId]?.totalBalanceYesterday {
            return BaseCurrencyAmount.fromDouble(totalBalance, baseCurrency)
        }
        return nil
    }
    
    public var nft: ApiNft? {
        accountSettings.for(accountId: accountId).backgroundNft
    }
    
    public var accentColor: UIColor {
        let index = accountSettings.for(accountId: accountId).accentColorIndex
        let color = getAccentColorByIndex(index)
        return color
    }
}
