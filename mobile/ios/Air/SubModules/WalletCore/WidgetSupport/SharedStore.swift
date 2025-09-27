//
//  SharedStore.swift
//  WalletCore
//
//  Created by nikstar on 23.09.2025.
//

import Foundation
import WalletContext

public actor SharedStore {
    private let cache: SharedCache

    public init(cache: SharedCache = SharedCache()) {
        self.cache = cache
    }

    @discardableResult
    public func reloadCache() async -> Bool {
        await cache.reload()
    }

    public func baseCurrency() async -> MBaseCurrency {
        await cache.baseCurrency
    }

    public func tokensDictionary() async -> [String: ApiToken] {
        await cache.tokens
    }

    public func tokens(sortedByName: Bool = true) async -> [ApiToken] {
        let tokens = await cache.tokens
        let values = Array(tokens.values)
        if sortedByName {
            return values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return values
    }

    public func token(slug: String) async -> ApiToken? {
        let tokens = await cache.tokens
        return tokens[slug]
    }

    public func ratesDictionary() async -> [String: MDouble] {
        await cache.rates
    }

    public func rate(for currency: MBaseCurrency) async -> MDouble? {
        let rates = await cache.rates
        return rates[currency.rawValue]
    }

    public func rateValue(for currency: MBaseCurrency) async -> Double? {
        let rates = await cache.rates
        guard let rate = rates[currency.rawValue] else { return nil }
        return rate.value
    }

    public func baseCurrencyRate() async -> Double {
        let base = await cache.baseCurrency
        let rates = await cache.rates
        return rates[base.rawValue]?.value ?? base.fallbackExchangeRate
    }
}
