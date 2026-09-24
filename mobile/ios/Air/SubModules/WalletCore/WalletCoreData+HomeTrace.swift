import WalletContext

extension WalletCoreData.Event {
    /// Deliberately logs event metadata, never balances, addresses, or activity payloads.
    public var homeTraceDescription: String? {
        switch self {
        case .balanceChanged(let id): "balanceChanged account=\(id)"
        case .rawBalancesChanged(let id): "rawBalancesChanged account=\(id)"
        case .notActiveAccountBalanceChanged: "notActiveAccountBalanceChanged"
        case .tokensChanged: "tokensChanged"
        case .swapTokensChanged: "swapTokensChanged"
        case .baseCurrencyChanged: "baseCurrencyChanged"
        case .activitiesChanged(let id, let updated, let replaced):
            "activitiesChanged account=\(id) updated=\(updated.count) replaced=\(replaced.count)"
        case .nftsChanged(let id): "nftsChanged account=\(id)"
        case .stakingAccountData(let data): "stakingAccountData account=\(data.accountId)"
        case .accountChanged(let id, let isNew): "accountChanged account=\(id) new=\(isNew)"
        case .accountNameChanged: "accountNameChanged"
        case .assetsAndActivityDataUpdated: "assetsAndActivityDataUpdated"
        case .hideTinyTransfersChanged: "hideTinyTransfersChanged"
        case .hideUnverifiedNftsChanged: "hideUnverifiedNftsChanged"
        case .hideNoCostTokensChanged: "hideNoCostTokensChanged"
        case .homeActivityVisibleItemsLimitChanged: "homeActivityVisibleItemsLimitChanged"
        case .homeWalletVisibleTokensLimitChanged: "homeWalletVisibleTokensLimitChanged"
        case .updatingStatusChanged: "updatingStatusChanged"
        case .applicationWillEnterForeground: "applicationWillEnterForeground"
        case .applicationDidEnterBackground: "applicationDidEnterBackground"
        case .updateBalances: "sdk.updateBalances"
        case .updateTokens: "sdk.updateTokens"
        case .updateCurrencyRates: "sdk.updateCurrencyRates"
        case .updateStaking: "sdk.updateStaking"
        case .newActivities: "sdk.newActivities"
        case .newLocalActivity: "sdk.newLocalActivity"
        case .initialActivities: "sdk.initialActivities"
        case .updateNfts: "sdk.updateNfts"
        default: nil
        }
    }
}
