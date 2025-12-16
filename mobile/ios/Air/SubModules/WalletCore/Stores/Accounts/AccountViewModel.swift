

import UIKit
import SwiftUI
import WalletContext
import Perception
import Dependencies
import SwiftNavigation

@Perceptible
public class AccountViewModel {
    
    public let source: AccountSource
    
    private(set) public var account: MAccount = DUMMY_ACCOUNT

    @PerceptionIgnored
    public var onAccountDeleted: () -> () = { }
    
    @PerceptionIgnored
    @Dependency(\.accountStore) private var accountStore
    @PerceptionIgnored
    @Dependency(\.accountSettings) private var accountSettings
    @PerceptionIgnored
    @Dependency(\.nftStore) private var nftStore
    @PerceptionIgnored
    @Dependency(\.balanceStore.accountBalanceData) private var balanceData
    
    private let accountIdProvider: AccountIdProvider
    @PerceptionIgnored
    private var observeAccount: ObserveToken?
    
    public convenience init(accountId: String?) {
        self.init(source: AccountSource(accountId))
    }
    
    public init(source: AccountSource) {
        self.source = source
        self.accountIdProvider = AccountIdProvider(source: source)
        observeAccount = observe { [weak self] in
            guard let self else { return }
            if let account = accountStore.accountsById[self.accountId] {
                self.account = account
            } else {
                onAccountDeleted()
            }
        }
    }
    
    public var accountId: String {
        get { accountIdProvider.accountId }
        set { accountIdProvider.accountId = newValue }
    }

    public var isCurrent: Bool {
        account.id == accountStore.currentAccountId
    }
    public var balance: BaseCurrencyAmount? {
        balanceData[accountId]?.totalBalance
    }
    public var balance24h: BaseCurrencyAmount? {
        balanceData[accountId]?.totalBalanceYesterday
    }
    public var balanceChange: Double? {
        balanceData[accountId]?.totalBalanceChange
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
