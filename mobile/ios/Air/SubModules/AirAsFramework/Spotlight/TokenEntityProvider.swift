import Foundation
import WalletContext
import WalletCore
import WalletCoreTypes

@MainActor
@available(iOS 18.4, *)
enum TokenEntityProvider {
    static func entries(recent: [TokenEntity], limitPerAccount: Int = 50) -> [TokenSpotlightEntry] {
        var tokens = TokenStore.tokens
        for token in TokenStore.swapAssets ?? [] where tokens[token.slug] == nil {
            tokens[token.slug] = token
        }
        var held = Set<String>()
        var tracked = Set<String>()
        for account in AccountStore.orderedAccounts {
            held.formUnion(topHoldingTokenSlugs(account: account, limit: limitPerAccount))
            tracked.formUnion(AssetsAndActivityDataStore.data(accountId: account.id)?.importedSlugs ?? [])
        }
        return entries(tokens: tokens, held: held, tracked: tracked, recent: recent)
    }

    static func entries(
        tokens: [String: ApiToken], held: Set<String>, tracked: Set<String>, recent: [TokenEntity]
    ) -> [TokenSpotlightEntry] {
        var candidates: [String: TokenSpotlightEntry] = [:]
        func append(_ entity: TokenEntity, priority: Int) {
            guard priority > (candidates[entity.id]?.priority ?? -1) else { return }
            candidates[entity.id] = TokenSpotlightEntry(entity: entity, priority: priority)
        }
        // Bound discovery content; held and explicitly tracked tokens remain eligible
        // even when there is no market price.
        for token in tokens.values.filter({ $0.isPopular == true }).sorted(by: { $0.slug < $1.slug }).prefix(100) {
            append(TokenEntity(token: token), priority: 1)
        }
        for token in ApiToken.defaultTokens.values {
            append(TokenEntity(token: tokens[token.slug] ?? token), priority: 2)
        }
        for chain in ApiChain.allCases {
            append(TokenEntity(token: tokens[chain.nativeToken.slug] ?? chain.nativeToken), priority: 2)
        }
        for entity in recent.prefix(20) {
            append(tokens[entity.id].map(TokenEntity.init(token:)) ?? entity, priority: 6)
        }
        for (slugs, priority) in [(tracked, 8), (held, 10)] {
            for slug in slugs {
                guard let token = tokens[slug] ?? ApiToken.defaultTokens[slug] ?? TokenEntity.nativeToken(slug: slug) else { continue }
                append(TokenEntity(token: token), priority: priority)
            }
        }
        return candidates.values.sorted { $0.entity.id < $1.entity.id }
    }

    private static func topHoldingTokenSlugs(
        account: MAccount,
        limit: Int
    ) -> [String] {
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
                let lhsName = lhs.token.name
                let rhsName = rhs.token.name
                if lhsName != rhsName {
                    return lhsName < rhsName
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
