//
//  SharedStore.swift
//  WalletCore
//
//  Created by nikstar on 23.09.2025.
//

import Foundation

public actor SharedStore {
    private let cache: SharedCache

    public init(cache: SharedCache = SharedCache()) {
        self.cache = cache
    }

    public func reloadCache() async {
        await cache.reload()
    }

    public func baseCurrency() async -> MBaseCurrency {
        await cache.baseCurrency
    }

    public func tokensDictionary() async -> [String: ApiToken] {
        let tokens = await cache.tokens
        return tokens.isEmpty ? ApiToken.defaultTokens : tokens
    }

    public func ratesDictionary() async -> [String: MDouble] {
        await cache.rates
    }
}
