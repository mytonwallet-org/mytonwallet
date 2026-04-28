//
//  MTokenBalance.swift
//  WalletCore
//
//  Created by Sina on 3/26/24.
//

import Foundation
import OrderedCollections
import WalletContext

public struct MTokenBalance: Equatable, Hashable, Sendable {
    public let tokenSlug: String
    public let balance: BigInt
    public let isStaking: Bool

    public var tokenID: TokenID {
        TokenID(slug: tokenSlug, isStaking: isStaking)
    }

    // Improvement: token can not be nil if TokenBalance exists
    public var token: ApiToken? { TokenStore.tokens[tokenSlug] }

    public var tokenPrice: Double?
    public let tokenPriceChange: Double?
    public let toBaseCurrency: Double?
    public let toBaseCurrency24h: Double?
    public let toUsd: Double?

    public init(tokenSlug: String, balance: BigInt, isStaking: Bool) {
        self.tokenSlug = tokenSlug
        self.balance = balance
        self.isStaking = isStaking
        if let token = TokenStore.getToken(slug: tokenSlug), let price = token.price, let priceUsd = token.priceUsd {
            tokenPrice = price
            tokenPriceChange = token.percentChange24h
            let amountDouble = balance.doubleAbsRepresentation(decimals: token.decimals)
            toBaseCurrency = amountDouble * price
            let priceYesterday = price * 100 / (100 + (token.percentChange24h ?? 0))
            toBaseCurrency24h = amountDouble * priceYesterday
            toUsd = amountDouble * priceUsd
        } else {
            tokenPrice = nil
            tokenPriceChange = nil
            toBaseCurrency = nil
            toBaseCurrency24h = nil
            toUsd = nil
        }
    }

    init(dictionary: [String: Any]) {
        tokenSlug = (dictionary["token"] as? [String: Any])?["slug"] as? String ?? ""
        isStaking = dictionary["isStaking"] as? Bool ?? false
        if let amountValue = (dictionary["balance"] as? String)?.components(separatedBy: "bigint:")[1] {
            balance = BigInt(amountValue) ?? 0
        } else {
            balance = 0
        }
        if let token = TokenStore.tokens[tokenSlug == STAKED_TON_SLUG ? "toncoin" : tokenSlug], let price = token.price {
            tokenPrice = price
            tokenPriceChange = token.percentChange24h
            let amountDouble = balance.doubleAbsRepresentation(decimals: token.decimals)
            toBaseCurrency = amountDouble * price
            let priceYesterday = price / (1 + (token.percentChange24h ?? 0) / 100)
            toBaseCurrency24h = amountDouble * priceYesterday
            toUsd = amountDouble * (token.priceUsd ?? 0)
        } else {
            tokenPrice = nil
            tokenPriceChange = nil
            toBaseCurrency = nil
            toBaseCurrency24h = nil
            toUsd = nil
        }
    }
}

extension MTokenBalance {
    public static func sortedForBalanceData(tokenBalances: [MTokenBalance],
                                            balances: [String: BigInt],
                                            defaultTokenSlugs: OrderedSet<String>,
                                            importedTokenSlugs: Set<String>) -> [MTokenBalance] {
        if let sortedForNewWallet = sortForNewWallet(tokens: tokenBalances,
                                                     tokenName: { $0.displayName ?? $0.tokenSlug },
                                                     tokenSlug: \.tokenSlug,
                                                     defaultTokenSlugs: defaultTokenSlugs,
                                                     importedTokenSlugs: importedTokenSlugs,
                                                     balances: balances) {
            return sortedForNewWallet
        }

        var sortedTokens = tokenBalances
        sortUnpinned(tokens: &sortedTokens,
                     tokenName: { $0.displayName ?? $0.tokenSlug },
                     tokenSlug: \.tokenSlug,
                     priorityTokenSlugs: defaultTokenSlugs,
                     amountInBaseCurrency: \.toUsd)
        return sortedTokens
    }

    /// ## Group / Sort Rules
    ///
    /// 1. **Pinned Tokens** (Most recent first)
    ///    - Token A (Pinned Last)
    ///    - Token D (Pinned First)
    ///
    /// 2. **Unpinned Tokens** (Non-zero balance)
    ///    Sorted by **Balance**. If balance is equal, then additionally sorted by **Name**
    ///    - Token E (Highest Balance)
    ///    - Token H (Lowest Balance)
    ///
    /// 3. **Unpinned Default Tokens** (Zero balance)
    ///    Sorted by **Default Token Order**
    ///
    /// 4. **Unpinned Tokens** (Zero balance)
    ///    Sorted by **Name**
    ///    - Token I (name: A...)
    ///    - Token L (name: Z...)
    public static func sortedForUI(tokenBalances: [MTokenBalance],
                                   assetsAndActivityData: MAssetsAndActivityData,
                                   balances: [String: BigInt],
                                   defaultTokenSlugs: OrderedSet<String>) -> [MTokenBalance] {
        pinnedFirst(
            tokens: sortedForBalanceData(
                tokenBalances: tokenBalances,
                balances: balances,
                defaultTokenSlugs: defaultTokenSlugs,
                importedTokenSlugs: assetsAndActivityData.importedSlugs
            ),
            assetsAndActivityData: assetsAndActivityData
        )
    }

    /// (TokenID, ApiToken) can represent ApiToken and ephemeral staking MTokenBalance
    public static func sortForUI(apiTokens: inout [(TokenID, ApiToken)],
                                 balances: [String: BigInt],
                                 defaultTokenSlugs: OrderedSet<String>,
                                 importedTokenSlugs: Set<String>) {
        let sortedForNewWallet = sortForNewWallet(tokens: apiTokens,
                                                  tokenName: \.1.name,
                                                  tokenSlug: \.1.slug,
                                                  defaultTokenSlugs: defaultTokenSlugs,
                                                  importedTokenSlugs: importedTokenSlugs,
                                                  balances: balances)
        if let sortedForNewWallet {
            apiTokens = sortedForNewWallet
        } else {
            sortUnpinned(tokens: &apiTokens,
                         tokenName: \.1.name,
                         tokenSlug: \.1.slug,
                         priorityTokenSlugs: defaultTokenSlugs,
                         amountInBaseCurrency: {
                             guard let balance = balances[$1.slug] else { return nil }
                             guard let price = $1.price else { return nil }
                             let balanceAsDouble = balance.doubleAbsRepresentation(decimals: $1.decimals)
                             return balanceAsDouble * price
                         })
        }
    }
    
    /// For new wallet, default tokens order is hardcoded. Imported tokens are sorted by regular rules.
    private static func sortForNewWallet<T>(tokens: [T],
                                            tokenName: (T) -> String,
                                            tokenSlug: (T) -> String,
                                            defaultTokenSlugs: OrderedSet<String>,
                                            importedTokenSlugs: Set<String>,
                                            balances: [String: BigInt]) -> [T]? {
        // For new wallet, there either no balance for key or balance is 0
        let totalBalance = balances.values.reduce(into: 0, +=)
        
        if totalBalance == 0 {
            var (defaultTokens, otherTokens) = tokens.partition { token in defaultTokenSlugs.contains(tokenSlug(token)) }
            guard !defaultTokens.isEmpty else { return nil }
            
            let indexedDefaultTokenSlugs = defaultTokenSlugs.lazy.enumerated().map { index, slug in (slug, index) }
            let defaultTokensOrder = Dictionary(uniqueKeysWithValues: indexedDefaultTokenSlugs)
            
            // 1. Sort default tokens. Their order is hardcoded in defaultTokenSlugs set
            defaultTokens.sort(by: { tokenA, tokenB in
                let orderA = defaultTokensOrder[tokenSlug(tokenA), default: 0]
                let orderB = defaultTokensOrder[tokenSlug(tokenB), default: 0]
                return orderA < orderB
            })
            
            // 2. Sort imported and other zero-balance tokens with regular rules
            sortUnpinned(tokens: &otherTokens,
                         tokenName: tokenName,
                         tokenSlug: tokenSlug,
                         priorityTokenSlugs: [],
                         amountInBaseCurrency: { _ in nil })
            
            defaultTokens.append(contentsOf: otherTokens)
            return defaultTokens
        } else { // otherwise wallet is not treated as new
            return nil
        }
    }

    /// Generic sort by balance and name
    private static func sortUnpinned<T>(tokens: inout [T],
                                        tokenName: (T) -> String,
                                        tokenSlug: (T) -> String,
                                        priorityTokenSlugs: OrderedSet<String>,
                                        amountInBaseCurrency: (T) -> Double?) {
        let priorityOrder = Dictionary(uniqueKeysWithValues: priorityTokenSlugs.enumerated().map { idx, slug in
            (slug, idx)
        })

        // 3. Sort unpinned tokens
        tokens.sort(by: { tokenA, tokenB in
            let amountInBaseCurrencyA = amountInBaseCurrency(tokenA) ?? 0
            let amountInBaseCurrencyB = amountInBaseCurrency(tokenB) ?? 0

            if amountInBaseCurrencyA != amountInBaseCurrencyB {
                // tokens with higher amount are shown closer to top of the list
                return amountInBaseCurrencyA > amountInBaseCurrencyB
            } else {
                let priorityA = priorityOrder[tokenSlug(tokenA)]
                let priorityB = priorityOrder[tokenSlug(tokenB)]
                if let priorityA, let priorityB, priorityA != priorityB {
                    return priorityA < priorityB
                } else if priorityA != nil {
                    return true
                } else if priorityB != nil {
                    return false
                }

                let nameA = tokenName(tokenA)
                let nameB = tokenName(tokenB)
                // - tokens with equal amount will be sorted by name
                // - tokens with 0 amount also sorted by name (as they have equal amount according to rule above)
                return nameA < nameB
            }
        })
    }

    public static func pinnedFirst(tokens: [MTokenBalance],
                                   assetsAndActivityData: MAssetsAndActivityData) -> [MTokenBalance] {
        let (pinnedTokens, unpinnedTokens) = partitionTokensByPinning(
            tokens: tokens,
            assetsAndActivityData: assetsAndActivityData
        )
        return pinnedTokens + unpinnedTokens
    }

    public static func partitionTokensByPinning(tokens: [MTokenBalance],
                                                assetsAndActivityData: MAssetsAndActivityData) -> (pinned: [MTokenBalance], unpinned: [MTokenBalance]) {
        var pinnedTokens: [(token: MTokenBalance, pinIndex: Int)] = []
        var unpinnedTokens: [MTokenBalance] = []

        for token in tokens {
            switch assetsAndActivityData.isTokenPinned(slug: token.tokenSlug, isStaked: token.isStaking) {
            case .pinned(let index):
                pinnedTokens.append((token, index))
            case .notPinned:
                unpinnedTokens.append(token)
            }
        }

        pinnedTokens.sort(by: { $0.pinIndex > $1.pinIndex })
        return (pinnedTokens.map(\.token), unpinnedTokens)
    }
}

extension MTokenBalance: CustomStringConvertible {
    public var description: String {
        "MTokenBalance<\(tokenSlug) = \(balance) (price=\(tokenPrice ?? -1) curr=\(toBaseCurrency ?? -1))>"
    }
}

extension MTokenBalance {
    public var displayName: String? {
        guard let apiToken = self.token else { return nil }
        return Self.displayName(apiToken: apiToken, isStaking: isStaking)
    }
    
    public static func displayName(apiToken: ApiToken, isStaking: Bool) -> String {
        if isStaking {
            apiToken.name + (isStaking ? " Staking" : "")
        } else {
            apiToken.name
        }
    }
}

public struct TokenID: Hashable, CustomDebugStringConvertible, Sendable {
    public let slug: String
    public let isStaking: Bool
    
    public var debugDescription: String { "slug: \(slug), isStaking: \(isStaking)" }
    
    public init(slug: String, isStaking: Bool) {
        self.slug = slug
        self.isStaking = isStaking
    }
}
