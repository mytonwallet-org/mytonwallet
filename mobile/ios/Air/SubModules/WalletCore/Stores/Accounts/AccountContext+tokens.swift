import Foundation

public extension AccountContext {
    var walletTokenPresentation: MTokenBalance.Presentation {
        if let walletTokensData {
            return walletTokensData.presentation
        }
        return MTokenBalance.presentationForUI(
            walletTokens: balances.map { slug, balance in
                MTokenBalance(
                    tokenSlug: slug,
                    balance: balance,
                    isStaking: false
                )
            },
            account: account,
            assetsAndActivityData: AssetsAndActivityDataStore.data(accountId: account.id) ?? .empty,
            hidesTokensWithNoCost: AppStorageHelper.hideNoCostTokens
        )
    }
}
