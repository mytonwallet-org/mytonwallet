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

public protocol StartupContextError: Error {
    var startupContextDescription: String { get }
    var underlyingStartupError: (any Error)? { get }
}

public struct WalletCoreStartupError: StartupContextError, @unchecked Sendable {
    public enum Step: String, Sendable {
        case accountStoreInitialLoad
    }

    public let step: Step
    public let bootstrapAccountCountHint: Int?
    public let underlyingError: any Error

    public init(step: Step, bootstrapAccountCountHint: Int?, underlyingStartupError: any Error) {
        self.step = step
        self.bootstrapAccountCountHint = bootstrapAccountCountHint
        self.underlyingError = underlyingStartupError
    }

    public var startupContextDescription: String {
        let accountCount = bootstrapAccountCountHint.map(String.init) ?? "unknown"
        return "component=walletCoreData step=\(step.rawValue) bootstrapAccountCountHint=\(accountCount)"
    }

    public var underlyingStartupError: (any Error)? {
        underlyingError
    }
}

public struct WalletCoreData {
    public enum Event: @unchecked Sendable {
        case balanceChanged(accountId: String)
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
        case rawBalancesChanged(accountId: String)
        case assetsAndActivityDataUpdated
        case hideTinyTransfersChanged
        case hideNoCostTokensChanged
        case homeWalletVisibleTokensLimitChanged
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
        case updateAccountConfig(ApiUpdate.UpdateAccountConfig)
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
        case exchangeWithLedger(apdu: String, callback: @MainActor (String?) async -> ())
        case isLedgerJettonIdSupported(callback: @MainActor (Bool?) async -> ())
        case isLedgerUnsafeSupported(callback: @MainActor (Bool?) async -> ())
        case getLedgerDeviceModel(callback: @MainActor (ApiLedgerDeviceModel?) async -> ())
        
    }
    
    public protocol EventsObserver: AnyObject {
        @MainActor func walletCore(event: Event)
    }

    private init() {}
    
    @MainActor private static var hasStartedMinimal = false
    @MainActor private static var hasStartedRemaining = false

    // ability to observe events
    final class WeakEventsObserver {
        weak var value: EventsObserver?
        init(value: EventsObserver?) {
            self.value = value
        }
    }
    @MainActor private(set) static var eventObservers = [WeakEventsObserver]()
    public static func add(eventObserver: EventsObserver & Sendable) {
        Task { @MainActor in
            WalletCoreData.eventObservers.append(WeakEventsObserver(value: eventObserver))
        }
    }
    @MainActor public static func remove(observer: EventsObserver) {
        WalletCoreData.eventObservers.removeAll { $0.value === nil || $0.value === observer }
    }
    @MainActor public static func removeObservers() {
        eventObservers.removeAll { it in
            (it.value is UIViewController) ||
            (it.value is UIView)
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
        Task { @MainActor in
            @Dependency(\.accountSettings) var _accountSettings
            let accountSettings = _accountSettings.for(accountId: account.id)
            AccountStore.walletVersionsData = nil
            DappsStore.updateDappCount()
            changeThemeColors(to: accountSettings.accentColorIndex)
            UIApplication.shared.sceneKeyWindow?.updateTheme()
            for observer in WalletCoreData.eventObservers {
                observer.value?.walletCore(event: .accountChanged(accountId: account.id, isNew: isNew))
            }
        }
    }

    @MainActor public static func startMinimal(db: any DatabaseWriter, bootstrapAccountCountHint: Int? = nil) async throws {
        guard !hasStartedMinimal else { return }
        _ = LogStore.shared
        log.info("**** WalletCoreData.startMinimal() **** \(Date().formatted(.iso8601), .public)")
        StartupTrace.beginInterval("walletCoreData.startMinimal")
        StartupTrace.mark("walletCoreData.startMinimal.begin")
        hasStartedMinimal = true
        var didSucceed = false
        defer {
            if didSucceed {
                StartupTrace.mark("walletCoreData.startMinimal.end")
                StartupTrace.endInterval("walletCoreData.startMinimal", details: "result=done")
            } else {
                hasStartedMinimal = false
                StartupTrace.endInterval("walletCoreData.startMinimal", details: "result=failed")
            }
        }
        SettingsStore.liveValue.use(db: db)
        StartupTrace.mark("walletCoreData.settings.ready")
        do {
            try AccountStore.use(db: db)
        } catch {
            let details = "step=accountStoreInitialLoad bootstrapAccountCountHint=\(bootstrapAccountCountHint.map(String.init) ?? "unknown") error=\(String(reflecting: error))"
            log.fault("wallet core minimal startup failed \(details, .public)")
            StartupTrace.mark("walletCoreData.accountStore.failed", details: details)
            throw WalletCoreStartupError(
                step: .accountStoreInitialLoad,
                bootstrapAccountCountHint: bootstrapAccountCountHint,
                underlyingStartupError: error
            )
        }
        let accountIds = Set(AccountStore.accountsById.keys)
        log.info("AccountStore loaded \(accountIds.count) accounts")
        StartupTrace.mark("walletCoreData.accountStore.ready", details: "accounts=\(accountIds.count)")
        await AccountSettingsStore.liveValue.use(db: db)
        StartupTrace.mark("walletCoreData.accountSettings.ready")
        await AccountConfigStore.liveValue.use()
        StartupTrace.mark("walletCoreData.accountConfig.ready")
        didSucceed = true
    }

    @MainActor public static func startDeferred(db: any DatabaseWriter) async {
        guard hasStartedMinimal else { return }
        guard !hasStartedRemaining else { return }
        hasStartedRemaining = true
        StartupTrace.beginInterval("walletCoreData.startDeferred")
        StartupTrace.mark("walletCoreData.startDeferred.begin")
        let accountIds = Set(AccountStore.accountsById.keys)
        await runDeferredStartupStep("activityStore") {
            await ActivityStore.use(db: db)
        }
        await runDeferredStartupStep("savedAddresses") {
            await SavedAddressesStore.liveValue.use(db: db)
        }
        await runDeferredStartupStep("tokenStore") {
            TokenStore.loadFromCache()
        }
        await runDeferredStartupStep("assetsAndActivity") {
            await AssetsAndActivityDataStore.use(db: db)
        }
        await runDeferredStartupStep("staking") {
            await StakingStore.use(db: db)
        }
        await runDeferredStartupStep("balances") {
            await BalancesStore.use(db: db)
        }
        await runDeferredStartupStep("balanceData") {
            await BalanceDataStore.use()
        }
        await runDeferredStartupStep("nftStore") {
            NftStore.loadFromCache(accountIds: accountIds)
        }
        await runDeferredStartupStep("domains") {
            await DomainsStore.liveValue.use(db: db)
        }
        await runDeferredStartupStep("autolock") {
            _ = AutolockStore.shared
        }
        StartupTrace.mark("walletCoreData.startDeferred.end")
        StartupTrace.endInterval("walletCoreData.startDeferred", details: "result=done")
    }

    @MainActor private static func runDeferredStartupStep(_ name: String, operation: @MainActor () async -> Void) async {
        StartupTrace.beginInterval("walletCoreData.deferred.\(name)")
        StartupTrace.mark("walletCoreData.deferred.begin", details: "step=\(name) essential=false")
        await operation()
        log.info("wallet core deferred startup step ready step=\(name, .public)")
        StartupTrace.mark("walletCoreData.deferred.ready", details: "step=\(name) essential=false")
        StartupTrace.endInterval("walletCoreData.deferred.\(name)", details: "result=done")
    }

    @MainActor public static func clean() async {
        await ActivityStore.clean()
        await AssetsAndActivityDataStore.clean()
        await StakingStore.clean()
        await BalancesStore.clean()
        await BalanceDataStore.clean()
        TokenStore.clean()
        NftStore.clean()
        SettingsStore.liveValue.clean()
        SavedAddressesStore.liveValue.clean()
        AccountSettingsStore.liveValue.clean()
        AccountConfigStore.liveValue.clean()
        DomainsStore.liveValue.clean()
        AccountStore.clean()
        ConfigStore.shared.clean()
        hasStartedMinimal = false
        hasStartedRemaining = false
    }
}
