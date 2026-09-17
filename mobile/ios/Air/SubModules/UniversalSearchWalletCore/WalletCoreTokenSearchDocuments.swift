import Foundation
import UniversalSearchCore
import WalletCore
import WalletCoreTypes

/// Shared token fields and signals. Callers decide which tokens are eligible.
public enum WalletCoreTokenSearchDocuments {
    public static func entityID(tokenSlug: String) -> SearchEntityID {
        SearchEntityID("token:\(tokenSlug)")
    }

    public static func documents(
        tokens: [ApiToken],
        balances: [MTokenBalance],
        trackedTokenSlugs: Set<String>,
        interactions: [WalletCoreSearchInteractionRecord] = []
    ) -> [SearchDocument] {
        var balanceBySlug: [String: (isHeld: Bool, baseCurrencyValue: Double)] = [:]
        for balance in balances {
            var aggregate = balanceBySlug[balance.tokenSlug] ?? (false, 0)
            aggregate.isHeld = aggregate.isHeld || balance.balance > 0
            if let value = balance.toBaseCurrency, value.isFinite {
                aggregate.baseCurrencyValue += max(0, value)
            }
            balanceBySlug[balance.tokenSlug] = aggregate
        }

        let interactionByID = Dictionary(
            interactions.map { ($0.entityID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var seenSlugs = Set<String>()
        return tokens
            .filter { seenSlugs.insert($0.slug).inserted }
            .map { token in
                let balance = balanceBySlug[token.slug]
                var traits: SearchTraits = []
                if balance?.isHeld == true {
                    traits.insert(.held)
                }
                if trackedTokenSlugs.contains(token.slug) {
                    traits.insert(.tracked)
                }
                if token.isPopular == true {
                    traits.insert(.popular)
                }
                if let price = token.priceUsd, price.isFinite, price > 0 {
                    traits.insert(.hasMarketData)
                }

                return document(
                    token: token,
                    signals: SearchSignals(
                        traits: traits,
                        baseCurrencyValue: balance?.baseCurrencyValue,
                        interaction: interactionByID[entityID(tokenSlug: token.slug)].map {
                            SearchInteractionSignal(
                                lastSelectedAt: $0.lastSelectedAt,
                                selectionCount: $0.selectionCount
                            )
                        }
                    )
                )
            }
            .sorted { $0.id < $1.id }
    }

    public static func document(
        token: ApiToken,
        signals: SearchSignals = .init()
    ) -> SearchDocument {
        var fieldCandidates: [(String?, SearchFieldKind, SearchFieldMatchPolicy)] = [
            (token.displayName(strippingLabelWhenShown: true), .title, .text),
            (token.name, .alias, .text),
            (token.localizedName, .alias, .text),
            (token.symbol, .symbol, .text),
            (token.slug, .identifier, .exact),
            (token.tokenAddress, .address, .exact),
            (token.label, .alias, .text),
            (token.chain.title, .keyword, .text),
            (token.chain.rawValue, .keyword, .text),
        ]
        fieldCandidates.append(contentsOf: (token.keywords ?? []).map {
            (Optional($0), .keyword, .text)
        })
        return SearchDocument(
            id: entityID(tokenSlug: token.slug),
            kind: token.isRwaStock ? .stock : .token,
            fields: makeSearchFields(fieldCandidates),
            attributes: makeSearchAttributes([
                (WalletCoreSearchAttributeKey.tokenSlug, token.slug),
                (WalletCoreSearchAttributeKey.iconURL, token.image),
            ]),
            signals: signals
        )
    }
}
