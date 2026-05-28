//
//  SharedStore.swift
//  WalletCore
//
//  Created by nikstar on 23.09.2025.
//

import Foundation
import WalletContext

private let log = Log("SharedStore")

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

    public func tokensDictionary(tryRemote: Bool) async -> [String: ApiToken] {
        var tokens = await cache.tokens
        if tokens.count < 20 || tryRemote {
            do {
                let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.mytonwallet.org/assets")!)
                tokens = try JSONDecoder().decode([ApiToken].self, from: data).dictionaryByKey(\.slug)
                await cache.setTokens(tokens)
            } catch {
                log.error("\(error)")
            }
        }
        return tokens
    }

    public func ratesDictionary() async -> [String: MDouble] {
        await cache.rates
    }
}
