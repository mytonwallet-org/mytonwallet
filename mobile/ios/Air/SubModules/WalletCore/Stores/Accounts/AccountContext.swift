import UIKit
import SwiftUI
import WalletContext
import Perception
import Dependencies
import SwiftNavigation

@Perceptible @propertyWrapper
public class AccountContext {
    
    private(set) public var account: MAccount = DUMMY_ACCOUNT

    public var wrappedValue: MAccount { account }
    public var projectedValue: AccountContext { self }

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
    @PerceptionIgnored
    @Dependency(\.savedAddresses) private var savedAddressesStore
    @PerceptionIgnored
    @Dependency(\.domains) private var domainsStore
    
    private let accountIdProvider: AccountIdProvider
    @PerceptionIgnored
    private var observeAccount: ObserveToken?
    
    public convenience init(accountId: String?) {
        self.init(source: AccountSource(accountId))
    }
    
    public init(source: AccountSource) {
        self.accountIdProvider = AccountIdProvider(source: source)
        observeAccount = observe { [weak self] in
            guard let self else { return }
            updateAccount()
        }
    }
    
    private func updateAccount() {
        if case .constant(let account) = source {
                self.account = account
        } else if let account = accountStore.accountsById[self.accountId] {
            self.account = account
        } else {
            // `account` property is not changed to keep UI stable during account deletion. Views can continue displaying the last valid account data while animation plays.
            onAccountDeleted()
        }
    }
    
    public var accountId: String {
        get { accountIdProvider.accountId }
        set {
            accountIdProvider.accountId = newValue
            updateAccount()
        }
    }
    public var source: AccountSource {
        accountIdProvider.source
    }

    public var isCurrent: Bool {
        account.id == accountStore.currentAccountId
    }
    public var balanceData: MAccountBalanceData? {
        balanceStore.accountBalanceData[accountId]
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
        stakingStore.stakingData(forAccountID: accountId)
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
    public var savedAddresses: SavedAddresses {
        savedAddressesStore.for(accountId: accountId)
    }
    public var settings: AccountSettings {
        accountSettings.for(accountId: accountId)
    }
    public var domains: Domains {
        domainsStore.for(accountId: accountId)
    }
    public func getLocalName(chain: ApiChain, address: String) -> String? {
        getMyAccountName(chain: chain, address: address) ?? getSavedAddressName(chain: chain, saveKey: address)
    }
    public func getMyAccountName(chain: ApiChain, address: String) -> String? {
        let matchingAccount = accountStore.orderedAccounts.first { account in
            if let info = account.getChainInfo(chain: chain), info.address == address || info.domain == address {
                return true
            }
            return false
        }
        return matchingAccount?.displayName
    }
    public func getSavedAddressName(chain: ApiChain, saveKey: String) -> String? {
        savedAddresses.get(chain: chain, address: saveKey)?.name
    }
}
