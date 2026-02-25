//
//  WalletCoreData.swift
//  WalletCore
//
//  Created by Sina on 3/26/24.
//

import Foundation
import WalletContext
import UIKit
import GRDB
import Dependencies

private let log = Log("WalletCoreData")

public struct WalletCoreData {
    public enum Event: @unchecked Sendable {
        case balanceChanged(accountId: String, isFirstUpdate: Bool)
        case notActiveAccountBalanceChanged
        case tokensChanged
        case swapTokensChanged
        case baseCurrencyChanged(to: MBaseCurrency)
        
        case nftsChanged(accountId: String)
        case nftFeaturedCollectionChanged(accountId: String)
        
        case activitiesChanged(accountId: String, updatedIds: [String], replacedIds: [String: String])
        
        case accountChanged(accountId: String, isNew: Bool)
        case accountNameChanged
        case accountDeleted(accountId: String)
        case accountsReset
        case stakingAccountData(MStakingData)
        case assetsAndActivityDataUpdated
        case hideTinyTransfersChanged
        case hideNoCostTokensChanged
        case cardBackgroundChanged(_ accountId: String, _ nft: ApiNft?)
        case accentColorNftChanged(_ accountId: String, _ nft: ApiNft?)
        case walletVersionsDataReceived
        case updatingStatusChanged
        case applicationDidEnterBackground
        case applicationWillEnterForeground
        
        case updateDapps
        case activeDappLoaded(dapp: ApiDapp)
        case dappsCountUpdated(accountId: String)
        case dappConnect(request: ApiUpdate.DappConnect)
        case dappSendTransactions(ApiUpdate.DappSendTransactions)
        case dappSignData(ApiUpdate.DappSignData)
        case dappDisconnect(accountId: String, origin: String)
        case dappLoading(ApiUpdate.DappLoading)
        
        case configChanged

        // updates matching api definition
        case newActivities(ApiUpdate.NewActivities)
        case newLocalActivity(ApiUpdate.NewLocalActivities)
        case initialActivities(ApiUpdate.InitialActivities)
        case updateAccount(ApiUpdate.UpdateAccount)
        case updateAccountDomainData(ApiUpdate.UpdateAccountDomainData)
        case updateBalances(ApiUpdate.UpdateBalances)
        case updateCurrencyRates(ApiUpdate.UpdateCurrencyRates)
        case updateStaking(ApiUpdate.UpdateStaking)
        case updateSwapTokens(ApiUpdate.UpdateSwapTokens)
        case updateTokens([String: Any])
        case updateNfts(ApiUpdate.UpdateNfts)
        case nftReceived(ApiUpdate.NftReceived)
        case nftSent(ApiUpdate.NftSent)
        case nftPutUpForSale(ApiUpdate.NftPutUpForSale)
        case exchangeWithLedger(apdu: String, callback: @Sendable (String?) async -> ())
        case isLedgerJettonIdSupported(callback: @Sendable (Bool?) async -> ())
        case isLedgerUnsafeSupported(callback: @Sendable (Bool?) async -> ())
        case getLedgerDeviceModel(callback: @Sendable (ApiLedgerDeviceModel?) async -> ())
        
    }
    
    public protocol EventsObserver: AnyObject {
        @MainActor func walletCore(event: Event)
    }

    private init() {}

    // ability to observe events
    final class WeakEventsObserver {
        weak var value: EventsObserver?
        init(value: EventsObserver?) {
            self.value = value
        }
    }
    @MainActor private(set) static var eventObservers = [WeakEventsObserver]()
    public static func add(eventObserver: EventsObserver) {
        Task { @MainActor in
            WalletCoreData.eventObservers.append(WeakEventsObserver(value: eventObserver))
        }
    }
    public static func remove(observer: EventsObserver) {
        Task { @MainActor in
            WalletCoreData.eventObservers.removeAll { $0.value === nil || $0.value === observer }
        }
    }
    @MainActor public static func removeObservers() {
        eventObservers.removeAll { it in
            (it.value is UIViewController) ||
            (it.value is UIView) ||
            (it.value is (any ObservableObject))
        }
    }

    public static func notify(event: WalletCoreData.Event) {
        DispatchQueue.main.async {
            WalletCoreData.eventObservers = WalletCoreData.eventObservers.compactMap { observer in
                if let observerInstance = observer.value {
                    observerInstance.walletCore(event: event)
                    return observer
                }
                return nil
            }
        }
    }

    public static func notifyAccountChanged(to account: MAccount, isNew: Bool) {
        @Dependency(\.accountSettings) var _accountSettings
        let accountSettings = _accountSettings.for(accountId: account.id)
        DispatchQueue.main.async {
            AccountStore.walletVersionsData = nil
            // Improvement: data race – reading via assetsAndActivityData(for:) can be called while writing
            let assetsAndActivityData = MAssetsAndActivityData(dictionary: AppStorageHelper.assetsAndActivityData(for: account.id))
            AccountStore.setAssetsAndActivityData(assetsAndActivityData, forAccountID: account.id)
            DappsStore.updateDappCount()
            changeThemeColors(to: accountSettings.accentColorIndex)
            UIApplication.shared.sceneKeyWindow?.updateTheme()
            for observer in WalletCoreData.eventObservers {
                observer.value?.walletCore(event: .accountChanged(accountId: account.id, isNew: isNew))
            }
        }
    }

    public static func start(db: any DatabaseWriter) async {
        _ = LogStore.shared
        log.info("**** WalletCoreData.start() **** \(Date().formatted(.iso8601), .public)")
        await ActivityStore.use(db: db)
        AccountStore.use(db: db)
        let accountIds = Set(AccountStore.accountsById.keys)
        log.info("AcountStore loaded \(accountIds.count) accounts")
        
        // Detect if this is new install and delete old keychain storage if needed
        let isFirstLaunch = await (UIApplication.shared.delegate as? MtwAppDelegateProtocol)?.isFirstLaunch == true
        if isFirstLaunch {
            log.info("First launch detected. Will check if accounts from previous install should can be deleted.")
        }
        if isFirstLaunch && accountIds.isEmpty && GlobalStorage.keysIn(key: "accounts")?.isEmpty != false {
            log.info("Deleting accounts from previous install")
            KeychainHelper.deleteAccountsFromPreviousInstall()
        }
        
        TokenStore.loadFromCache()
        StakingStore.use(db: db)
        BalanceStore.loadFromCache(accountIds: accountIds)
        NftStore.loadFromCache(accountIds: accountIds)
        _ = AccountSettingsStore.liveValue
        _ = DomainsStore.liveValue
        _ = AutolockStore.shared
    }

    public static func clean() async {
        await ActivityStore.clean()
        BalanceStore.clean()
        TokenStore.clean()
        NftStore.clean()
        AccountStore.clean()
        ConfigStore.shared.clean()
    }
}
