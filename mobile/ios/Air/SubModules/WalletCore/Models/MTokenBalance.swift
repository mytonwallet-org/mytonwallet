//
//  MTokenBalance.swift
//  WalletCore
//
//  Created by Sina on 3/26/24.
//

import Foundation
import OrderedCollections
import WalletContext

// FIXME: - Hashable invariant violation: equal values MUST have equal hashes
// default compiler generated implementation of `hash(into:)` is inconsistent with custom `==`
public struct MTokenBalance: Equatable, Hashable, Sendable {
    public static func == (lhs: MTokenBalance, rhs: MTokenBalance) -> Bool {
        lhs.tokenSlug == rhs.tokenSlug && lhs.isStaking == rhs.isStaking
    }

    public let tokenSlug: String
    public let balance: BigInt
    public let isStaking: Bool

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
    /// 3. **Unpinned Tokens** (Zero balance)
    ///    Sorted by **Name**
    ///    - Token I (name: A...)
    ///    - Token L (name: Z...)
    public static func sortedForUI(tokenBalances: [MTokenBalance],
                                   assetsAndActivityData: MAssetsAndActivityData) -> [MTokenBalance] {
        var unpinnedTokens: [MTokenBalance] = []

        let sortedPinnedTokens: [MTokenBalance]
        do { // 1. Split into 2 groups
            var _pinnedTokens: [(token: MTokenBalance, pinIndex: Int)] = []
            tokenBalances.forEach { token in
                switch assetsAndActivityData.isTokenPinned(slug: token.tokenSlug, isStaked: token.isStaking) {
                case .pinned(let index): _pinnedTokens.append((token, index))
                case .notPinned: unpinnedTokens.append(token)
                }
            }

            // 2. Sort pinned tokens. Last pinned token is shown at the top of the list.
            _pinnedTokens.sort(by: { $0.pinIndex > $1.pinIndex })
            sortedPinnedTokens = _pinnedTokens.map { $0.token }
        }

        // 3. Sort unpinned tokens
        sortUnpinned(tokens: &unpinnedTokens,
                     tokenName: { $0.displayName ?? $0.tokenSlug },
                     amountInBaseCurrency: \.toUsd)

        return sortedPinnedTokens + unpinnedTokens
    }

    /// (TokenID, ApiToken) can represent ApiToken and ephemeral staking MTokenBalance
    public static func sortForUI(apiTokens: inout [(TokenID, ApiToken)],
                                 balances: [String: BigInt]) {
        sortUnpinned(tokens: &apiTokens,
                     tokenName: \.1.name,
                     amountInBaseCurrency: {
                         guard let balance = balances[$1.slug] else { return nil }
                         guard let price = $1.price else { return nil }
                         let balanceAsDouble = balance.doubleAbsRepresentation(decimals: $1.decimals)
                         return balanceAsDouble * price
                     })
    }

    /// Generic sort by balance and name
    private static func sortUnpinned<T>(tokens: inout [T],
                                        tokenName: (T) -> String,
                                        amountInBaseCurrency: (T) -> Double?) {
        // 3. Sort unpinned tokens
        tokens.sort(by: { tokenA, tokenB in
            let amountInBaseCurrencyA = amountInBaseCurrency(tokenA) ?? 0
            let amountInBaseCurrencyB = amountInBaseCurrency(tokenB) ?? 0

            if amountInBaseCurrencyA != amountInBaseCurrencyB {
                // tokens with higher amount are shown closer to top of the list
                return amountInBaseCurrencyA > amountInBaseCurrencyB
            } else {
                let nameA = tokenName(tokenA)
                let nameB = tokenName(tokenB)
                // - tokens with equal amount will be sorted by name
                // - tokens with 0 amount also sorted by name (as they have equal amount according to rule above)
                return nameA < nameB
            }
        })
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

public struct TokenID: Hashable, CustomDebugStringConvertible {
    public let slug: String
    public let isStaking: Bool
    
    public var debugDescription: String { "slug: \(slug), isStaking: \(isStaking)" }
    
    public init(slug: String, isStaking: Bool) {
        self.slug = slug
        self.isStaking = isStaking
    }
}
