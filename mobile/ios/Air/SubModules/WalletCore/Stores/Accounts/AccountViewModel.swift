

import UIKit
import SwiftUI
import WalletContext
import Perception
import Dependencies
import SwiftNavigation

@Perceptible @propertyWrapper
public class AccountViewModel {
    
    public let source: AccountSource
    
    private(set) public var account: MAccount = DUMMY_ACCOUNT

    public var wrappedValue: MAccount { account }
    public var projectedValue: AccountViewModel { self }

    @PerceptionIgnored
    public var onAccountDeleted: () -> () = { }
    
    @PerceptionIgnored
    @Dependency(\.accountStore) private var accountStore
    @PerceptionIgnored
    @Dependency(\.accountSettings) private var accountSettings
    @PerceptionIgnored
    @Dependency(\.nftStore) private var nftStore
    @PerceptionIgnored
    @Dependency(\.balanceStore) private var balanceStore
    @PerceptionIgnored
    @Dependency(\.stakingStore) private var stakingStore
    
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
        balanceStore.accountBalanceData[accountId]?.totalBalance
    }
    public var balance24h: BaseCurrencyAmount? {
        balanceStore.accountBalanceData[accountId]?.totalBalanceYesterday
    }
    public var balanceChange: Double? {
        balanceStore.accountBalanceData[accountId]?.totalBalanceChange
    }
    public var balances: [String: BigInt] {
        balanceStore.getAccountBalances(accountId: accountId)
    }
    public var nft: ApiNft? {
        accountSettings.for(accountId: accountId).backgroundNft
    }
    public var accentColor: UIColor {
        let index = accountSettings.for(accountId: accountId).accentColorIndex
        let color = getAccentColorByIndex(index)
        return color
    }
    public var stakingData: MStakingData? {
        stakingStore.byId(accountId)
    }
    public func getStakingBadgeContent(tokenSlug: String, isStaking: Bool) -> StakingBadgeContent? {
        guard let stakingState = stakingData?.bySlug(tokenSlug) else { return nil }
        if isStaking, stakingState.balance > 0 {
            return StakingBadgeContent(isActive: true, yieldType: stakingState.yieldType, yieldValue: stakingState.apy)
        } else if !isStaking, stakingState.balance == 0 {
            return StakingBadgeContent(isActive: false, yieldType: stakingState.yieldType, yieldValue: stakingState.apy)
        }
        return nil
    }
}
