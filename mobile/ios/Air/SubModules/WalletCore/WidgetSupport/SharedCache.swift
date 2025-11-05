//
//  SharedCache.swift
//  WalletCore
//
//  Created by nikstar on 23.09.2025.
//

import Foundation
import WalletContext

public actor SharedCache {
    public var tokens: [String: ApiToken] = _TokenStore.defaultTokens
    public var baseCurrency: MBaseCurrency = .USD
    public var rates: [String: MDouble] = [:]

    private struct Snapshot: Codable, Sendable {
        var tokens: [String: ApiToken]
        var baseCurrency: MBaseCurrency
        var rates: [String: MDouble]
    }

    private let url = appGroupContainerUrl?.appending(component: "cache.json")

    public init() {
        Task { await loadFromDisk() }
    }

    public func reload() {
        loadFromDisk()
    }

    public func setTokens(_ tokens: [String: ApiToken]) {
        self.tokens = tokens
        persist()
    }

    public func setBaseCurrency(_ baseCurrency: MBaseCurrency) {
        self.baseCurrency = baseCurrency
        persist()
    }

    public func setRates(_ rates: [String: MDouble]) {
        self.rates = rates
        persist()
    }

    public func update(tokens: [String: ApiToken]? = nil, baseCurrency: MBaseCurrency? = nil, rates: [String: MDouble]? = nil) {
        var didChange = false

        if let tokens {
            self.tokens = tokens
            didChange = true
        }

        if let baseCurrency {
            self.baseCurrency = baseCurrency
            didChange = true
        }

        if let rates {
            self.rates = rates
            didChange = true
        }

        if didChange {
            persist()
        }
    }

    public func save() {
        persist()
    }

    private func loadFromDisk() {
        do {
            guard let url else { return }
            let data = try Data(contentsOf: url)
            let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            self.tokens = snapshot.tokens
            self.baseCurrency = snapshot.baseCurrency
            self.rates = snapshot.rates
        } catch {
        }
    }

    private func persist() {
        guard let url else { return }
        let snapshot = Snapshot(tokens: tokens, baseCurrency: baseCurrency, rates: rates)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
        }
    }
}
