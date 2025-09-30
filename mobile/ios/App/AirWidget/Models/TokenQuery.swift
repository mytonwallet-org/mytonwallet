//
//  TokenQuery.swift
//  App
//
//  Created by nikstar on 23.09.2025.
//

import AppIntents
import WalletCore
import WidgetKit
import WalletContext

extension ApiToken: @retroactive AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Token", bundle: LocalizationSupport.shared.bundle))
    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(symbol)", subtitle: "\(name)")
    }
    public static var defaultQuery = TokenQuery()
}

public struct TokenQuery: EntityStringQuery {

    public init() {}
    
    public func entities(for identifiers: [ApiToken.ID]) async throws -> [ApiToken] {
        let tokens = await loadTokens()
        let dict = Dictionary(uniqueKeysWithValues: tokens.map { ($0.id, $0) })
        return identifiers.compactMap { dict[$0] }
    }

    public func suggestedEntities() async throws -> IntentItemCollection<ApiToken> {
        let tokens = await loadTokens()
            .filter { $0.priceUsd?.nilIfZero != nil }
        let popular = tokens
            .filter { $0.isPopular == true }
//        let notPopular = tokens
//            .filter { $0.isPopular != true }  
        return IntentItemCollection {
            ItemSection(LocalizedStringResource("Popular", bundle: LocalizationSupport.shared.bundle), items: popular)
//            ItemSection(LocalizedStringResource("All Tokens", bundle: LocalizationSupport.shared.bundle), items: notPopular)
        }
    }

    public func entities(matching string: String) async throws -> IntentItemCollection<ApiToken> {
        let string = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = await loadTokens()
            .filter { $0.priceUsd?.nilIfZero != nil }
            .filter { $0.matchesSearch(string) }
        return IntentItemCollection {
            ItemSection(LocalizedStringResource("All Tokens", bundle: LocalizationSupport.shared.bundle), items: tokens)
        }
    }

    private func loadTokens() async -> [ApiToken] {
        let store = SharedStore()
        _ = await store.reloadCache()
        let tokens = await store.tokensDictionary(tryRemote: false)
        return Array(tokens.values)
    }
}
