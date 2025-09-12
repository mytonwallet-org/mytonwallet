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

public struct WalletCoreData {
    public enum Event: @unchecked Sendable {
        case balanceChanged(isFirstUpdate: Bool)
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
        case dappsCountUpdated
        case dappConnect(request: ApiUpdate.DappConnect)
        case dappSendTransactions(MDappSendTransactions)
        case dappDisconnect(accountId: String, origin: String)
        
        case configChanged

        // updates matching api definition
        case newActivities(ApiUpdate.NewActivities)
        case newLocalActivity(ApiUpdate.NewLocalActivities)
        case initialActivities(ApiUpdate.InitialActivities)
        case updateBalances(ApiUpdate.UpdateBalances)
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
        
        case minimizedSheetChanged(_ state: MinimizedSheetState)
        case sheetDismissed(UIViewController)
    }
    
    public protocol EventsObserver: AnyObject {
        @MainActor func walletCore(event: Event)
    }

    private init() {}
    static let queue = DispatchQueue(label: "org.mytonwallet.app.wallet_core_background", attributes: .concurrent)
    static let processorQueue = DispatchQueue(label: "org.mytonwallet.app.wallet_core_background_processor", attributes: .concurrent)

    // ability to observe events
    class WeakEventsObserver {
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

    public static func notify(event: WalletCoreData.Event, for accountId: String? = nil) {
        guard accountId == nil || accountId == AccountStore.account?.id else {
            return
        }
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
        DispatchQueue.main.async {
            AccountStore.walletVersionsData = nil
            AccountStore.setAssetsAndActivityData(accountId: account.id, value: MAssetsAndActivityData(dictionary: AppStorageHelper.assetsAndActivityData(for: account.id)))
            DappsStore.updateDappCount()
            changeThemeColors(to: AccountStore.currentAccountAccentColorIndex)
            (UIApplication.shared.sceneKeyWindow as? WThemedView)?.updateTheme()
            for observer in WalletCoreData.eventObservers {
                observer.value?.walletCore(event: .accountChanged(accountId: account.id, isNew: isNew))
            }
        }
    }

    public static func start(db: any DatabaseWriter) async {
        _ = LogStore.shared
        Log.shared.info("**** WalletCoreData.start() **** \(Date().formatted(.iso8601), .public)")
        await ActivityStore.use(db: db)
        AccountStore.use(db: db)
        let accountIds = Set(AccountStore.accountsById.keys)
        TokenStore.loadFromCache()
        await StakingStore.use(db: db)
        BalanceStore.loadFromCache(accountIds: accountIds)
        NftStore.loadFromCache(accountIds: accountIds)
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
