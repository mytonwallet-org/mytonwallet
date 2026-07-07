import Foundation
import WalletContext
import WalletCore
import WalletCoreTypes

@MainActor
@available(iOS 18.4, *)
enum TokenEntityProvider {
    static func suggestedEntities(limitPerAccount: Int = 50) -> [TokenEntity] {
        candidateTokenSlugs(limitPerAccount: limitPerAccount)
            .map(resolve(tokenSlug:))
    }

    private static func resolve(tokenSlug: String) -> TokenEntity {
        if let token = TokenStore.getToken(slug: tokenSlug) ?? TokenEntity.nativeToken(slug: tokenSlug) {
            return TokenEntity(token: token)
        }
        return TokenEntity.resolve(tokenSlug: tokenSlug)
    }

    private static func candidateTokenSlugs(limitPerAccount: Int) -> [String] {
        var tokenSlugs: [String] = []
        var seenTokenSlugs = Set<String>()

        func append(_ tokenSlug: String) {
            let tokenSlug = tokenSlug.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !tokenSlug.isEmpty, seenTokenSlugs.insert(tokenSlug).inserted else { return }
            tokenSlugs.append(tokenSlug)
        }

        for account in AccountStore.orderedAccounts {
            topHoldingTokenSlugs(account: account, limit: limitPerAccount).forEach(append)
            ApiToken.defaultSlugs(forNetwork: account.network, account: account).forEach(append)
        }

        ApiChain.allCases.map { $0.nativeToken.slug }.forEach(append)
        return tokenSlugs
    }

    private static func topHoldingTokenSlugs(account: MAccount, limit: Int) -> [String] {
        let tokenBalances = BalanceDataStore.walletTokensData(accountId: account.id)?.walletTokens ?? []
        return tokenBalances
            .filter { $0.balance > 0 }
            .compactMap { tokenBalance -> (tokenBalance: MTokenBalance, token: ApiToken)? in
                guard let token = TokenStore.getToken(slug: tokenBalance.tokenSlug) else {
                    return nil
                }
                return (tokenBalance, token)
            }
            .sorted { lhs, rhs in
                let lhsValue = sortableBalanceValue(lhs.tokenBalance, token: lhs.token)
                let rhsValue = sortableBalanceValue(rhs.tokenBalance, token: rhs.token)
                if lhsValue != rhsValue {
                    return lhsValue > rhsValue
                }
                if lhs.token.name != rhs.token.name {
                    return lhs.token.name < rhs.token.name
                }
                return lhs.token.slug < rhs.token.slug
            }
            .prefix(limit)
            .map(\.token.slug)
    }

    private static func sortableBalanceValue(_ tokenBalance: MTokenBalance, token: ApiToken) -> Double {
        tokenBalance.toUsd
            ?? tokenBalance.toBaseCurrency
            ?? tokenBalance.balance.doubleAbsRepresentation(decimals: token.decimals)
    }
}
