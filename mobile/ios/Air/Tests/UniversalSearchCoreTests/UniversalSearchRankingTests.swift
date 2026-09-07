import Foundation
import Testing
import UniversalSearchCore

@Suite("Universal Search ranking")
struct UniversalSearchRankingTests {
    private let engine = UniversalSearchEngine()
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test
    func `stronger text relevance beats selection history`() {
        let exact = document(id: "token:exact", title: "Wallet")
        let selectedSubstring = document(
            id: "token:selected",
            title: "My Wallet Coin",
            interaction: .init(lastSelectedAt: now, selectionCount: 50)
        )

        let results = engine.search("wallet", in: [selectedSubstring, exact], now: now)

        #expect(results.map(\.id) == [exact.id, selectedSubstring.id])
    }

    @Test
    func `connected apps retain priority over selected held tokens`() {
        let connectedApp = document(
            id: "app:gram",
            kind: .application,
            title: "Gram",
            traits: [.connected]
        )
        let heldToken = document(
            id: "token:gram",
            title: "Gram",
            traits: [.held],
            interaction: .init(lastSelectedAt: now, selectionCount: 1)
        )

        #expect(engine.search("gram", in: [heldToken, connectedApp], now: now).first?.id == connectedApp.id)
        #expect(engine.search(
            "gram",
            in: [withoutInteraction(heldToken), connectedApp],
            now: now
        ).first?.id == connectedApp.id)
    }

    @Test
    func `product result priorities precede history within comparable matches`() {
        let kinds: [(String, SearchEntityKind, SearchTraits)] = [
            ("external-wallet", .wallet, [.external, .viewOnly]),
            ("connected-app", .application, [.connected]),
            ("held-token", .token, [.held]),
            ("tracked-token", .token, [.tracked]),
            ("collectible", .collectible, [.owned]),
            ("collection", .collection, [.owned]),
            ("my-wallet", .wallet, [.owned]),
            ("view-wallet", .wallet, [.owned, .viewOnly]),
            ("send", .walletAction, []),
            ("appearance", .setting, []),
            ("popular-token", .stock, [.popular]),
            ("popular-app", .application, [.popular]),
            ("site", .site, [.fromHistory]),
            ("recent-search", .webSearchHistory, [.fromHistory]),
            ("chat", .agentChat, [.fromHistory]),
            ("agent", .agentAction, []),
        ]
        let documents = kinds.enumerated().map { index, entry in
            document(
                id: entry.0, kind: entry.1, title: "Wallet", traits: entry.2,
                interaction: .init(lastSelectedAt: now, selectionCount: index)
            )
        }
        #expect(engine.search("wallet", in: Array(documents.reversed()), now: now).map(\.id) == documents.map(\.id))
    }

    @Test
    func `recommendations break ties but do not beat relevance`() {
        let source = SearchSourceID("backend:recommendations")
        let recommended = document(
            id: "app:recommended",
            kind: .application,
            title: "My Wallet App",
            recommendation: .init(source: source, score: 1)
        )
        let exact = document(
            id: "app:exact",
            kind: .application,
            title: "Wallet"
        )
        let lowerRecommendation = document(
            id: "app:lower",
            kind: .application,
            title: "Wallet",
            recommendation: .init(source: source, score: 0.2)
        )
        let higherRecommendation = document(
            id: "app:higher",
            kind: .application,
            title: "Wallet",
            recommendation: .init(source: source, score: 0.9)
        )

        #expect(engine.search("wallet", in: [recommended, exact], now: now).first?.id == exact.id)
        #expect(engine.search(
            "wallet",
            in: [lowerRecommendation, higherRecommendation],
            now: now
        ).first?.id == higherRecommendation.id)
    }

    @Test
    func `expired recommendations are neutral and fresh beats stale`() {
        let source = SearchSourceID("backend:trending")
        let expired = document(
            id: "token:expired",
            title: "Gram",
            recommendation: .init(
                source: source,
                score: 1,
                expiresAt: now.addingTimeInterval(-10)
            )
        )
        let fresh = document(
            id: "token:fresh",
            title: "Gram",
            recommendation: .init(
                source: source,
                score: 0.1,
                expiresAt: now.addingTimeInterval(10)
            )
        )
        let stale = document(
            id: "token:stale",
            title: "Gram",
            recommendation: .init(
                source: source,
                score: 1,
                expiresAt: now.addingTimeInterval(-10),
                staleUntil: now.addingTimeInterval(10)
            )
        )

        #expect(engine.search("gram", in: [expired, fresh], now: now).first?.id == fresh.id)
        #expect(engine.search("gram", in: [stale, fresh], now: now).first?.id == fresh.id)
    }

    @Test
    func `held tokens use balance before recommendation`() {
        let source = SearchSourceID("backend:trending")
        let largerBalance = document(
            id: "token:large",
            title: "USD",
            traits: [.held],
            baseCurrencyValue: 1_000
        )
        let recommendedSmallBalance = document(
            id: "token:small",
            title: "USD",
            traits: [.held],
            baseCurrencyValue: 10,
            recommendation: .init(source: source, score: 1)
        )

        #expect(engine.search(
            "usd",
            in: [recommendedSmallBalance, largerBalance],
            now: now
        ).first?.id == largerBalance.id)
    }

    @Test
    func `held exact title beats unheld token copying title into symbol`() {
        let native = document(
            id: "token:solana",
            title: "Solana",
            traits: [.held]
        )
        let copy = SearchDocument(
            id: SearchEntityID("token:copy"),
            kind: .token,
            fields: [
                .init("Prisma Staked SOL", kind: .title),
                .init("Solana", kind: .symbol),
            ]
        )

        #expect(engine.search("Solana", in: [copy, native], now: now).first?.id == native.id)
    }

    @Test
    func `curated Fragment app beats unknown zero-value tokens for incremental queries`() {
        let app = document(
            id: "app:fragment",
            kind: .application,
            title: "Fragment",
            traits: [.curated, .popular]
        )
        let unknownTokens = [
            document(id: "token:fragment-1", title: "FRAGMENT"),
            document(id: "token:fragment-2", title: "Fragment @zxcurside"),
        ]

        for query in ["fra", "frag", "fragme", "fragment"] {
            #expect(engine.search(query, in: unknownTokens + [app], now: now).first?.id == app.id)
        }
    }

    @Test
    func `trust can beat finer text precision inside a strong relevance band`() {
        let app = document(
            id: "app:fragment",
            kind: .application,
            title: "Fragment",
            traits: [.curated]
        )
        let exactTicker = SearchDocument(
            id: SearchEntityID("token:frag"),
            kind: .token,
            fields: [
                .init("Unrelated Token", kind: .title),
                .init("FRAG", kind: .symbol),
            ]
        )

        let results = engine.search("frag", in: [exactTicker, app], now: now)

        #expect(results.first?.id == app.id)
        #expect(results.first?.rank.relevanceBand == .phrase)
        #expect(results.first?.rank.trustTier == .curated)
    }

    @Test
    func `personal relevance beats catalog trust within the same relevance band`() {
        let app = document(
            id: "app:fragment",
            kind: .application,
            title: "Fragment",
            traits: [.verified, .curated]
        )
        let heldToken = document(
            id: "token:fragment",
            title: "Fragment",
            traits: [.held]
        )

        #expect(engine.search("fragment", in: [app, heldToken], now: now).first?.id == heldToken.id)
    }

    @Test
    func `weak description match cannot beat a strong title match`() {
        let titleToken = document(id: "token:fragment", title: "Fragment")
        let catalogApp = SearchDocument(
            id: SearchEntityID("app:description"),
            kind: .application,
            fields: [
                .init("Marketplace", kind: .title),
                .init("Trade Fragment collectibles", kind: .description),
            ],
            signals: .init(traits: [.verified, .curated])
        )

        #expect(engine.search(
            "fragment",
            in: [catalogApp, titleToken],
            now: now
        ).first?.id == titleToken.id)
    }

    @Test
    func `exact identifiers remain authoritative over verified text results`() {
        let identifier = SearchDocument(
            id: SearchEntityID("token:fragment"),
            kind: .token,
            fields: [.init("fragment", kind: .identifier, matchPolicy: .exact)]
        )
        let verifiedApp = document(
            id: "app:fragment",
            kind: .application,
            title: "Fragment",
            traits: [.verified]
        )

        #expect(engine.search(
            "fragment",
            in: [verifiedApp, identifier],
            now: now
        ).first?.id == identifier.id)
    }

    @Test
    func `verified curated and market-data trust tiers are ordered`() {
        let unknown = document(id: "token:unknown", title: "Asset")
        let established = document(
            id: "token:established",
            title: "Asset",
            traits: [.hasMarketData]
        )
        let curated = document(
            id: "app:curated",
            kind: .application,
            title: "Asset",
            traits: [.curated]
        )
        let verified = document(
            id: "app:verified",
            kind: .application,
            title: "Asset",
            traits: [.verified]
        )

        #expect(engine.search(
            "asset",
            in: [unknown, established, curated, verified],
            now: now
        ).map(\.id) == [verified.id, curated.id, established.id, unknown.id])
    }

    @Test
    func `deduplicates stable entity identities deterministically`() {
        let weak = document(id: "token:gram", title: "My Gram Token")
        let strong = document(id: "token:gram", title: "Gram")
        let other = document(id: "token:other", title: "Gram")

        let results = engine.search("gram", in: [weak, other, strong], now: now)

        #expect(results.count == 2)
        #expect(results.first?.id == strong.id)
        #expect(results.first?.match.kind == .exactPhrase)
    }

    private func document(
        id: String,
        kind: SearchEntityKind = .token,
        title: String,
        traits: SearchTraits = [],
        baseCurrencyValue: Double? = nil,
        interaction: SearchInteractionSignal? = nil,
        recommendation: SearchRankedSignal? = nil
    ) -> SearchDocument {
        SearchDocument(
            id: SearchEntityID(id),
            kind: kind,
            fields: [.init(title, kind: .title)],
            signals: .init(
                traits: traits,
                baseCurrencyValue: baseCurrencyValue,
                interaction: interaction,
                recommendation: recommendation
            )
        )
    }

    private func withoutInteraction(_ document: SearchDocument) -> SearchDocument {
        var signals = document.signals
        signals.interaction = nil
        return SearchDocument(
            id: document.id,
            kind: document.kind,
            fields: document.fields,
            matchRequirement: document.matchRequirement,
            attributes: document.attributes,
            signals: signals
        )
    }
}
