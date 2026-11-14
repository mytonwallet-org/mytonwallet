import Foundation
import Testing
import UIUniversalSearch
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletCore
@testable import UniversalSearchFeature

@Suite("Universal Search index service", .serialized)
@MainActor
struct UniversalSearchIndexServiceTests {
    @Test
    func `replacing an immediate refresh does not starve indexing`() async throws {
        let source = RecordingSource()
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context("account-a") },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero)
        )
        service.start()
        defer { service.stop() }

        // Once maxPostpone is reached, multiple events can replace zero-delay tasks
        // before any of them gets its first turn on MainActor.
        service.setWalletReady(true)
        service.walletCore(event: .tokensChanged)
        service.walletCore(event: .tokensChanged)

        try await waitUntil { await coordinator.search("token").hits.count == 1 }
        let result = await coordinator.search("token")
        #expect(result.hits.map(\.id.rawValue) == ["token:account-a"])
        #expect(await source.contexts == [context("account-a")])
    }

    @Test
    func `stop and restart discard queued refreshes`() async throws {
        let source = RecordingSource()
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let selection = Selection()
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context(selection.accountID) },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero)
        )
        service.start()
        service.setWalletReady(true)
        service.stop()
        selection.accountID = "account-b"
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }

        try await waitUntil { await coordinator.search("token").hits.count == 1 }
        #expect(await source.contexts == [context("account-b")])
        #expect(await coordinator.search("token").hits.map(\.id.rawValue) == ["token:account-b"])
    }

    @Test
    func `wallet restart during a refresh keeps pending work for the latest account`() async throws {
        let source = RecordingSource(holdsFirstSnapshot: true)
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let selection = Selection()
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context(selection.accountID) },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero)
        )
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }
        try await waitUntil { await source.isHoldingSnapshot }

        service.setWalletReady(false)
        selection.accountID = "account-b"
        service.setWalletReady(true)
        service.walletCore(event: .tokensChanged)
        await source.releaseSnapshot()

        try await waitUntil {
            await coordinator.search("token").hits.map(\.id.rawValue) == ["token:account-b"]
        }
        #expect(await source.contexts == [context("account-a"), context("account-b")])
    }

    @Test
    func `invalidations during a refresh coalesce into one follow up`() async throws {
        let source = RecordingSource(holdsFirstSnapshot: true)
        let coordinator = UniversalSearchCoordinator(sources: [source])
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context("account-a") },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .milliseconds(10))
        )
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }
        try await waitUntil { await source.isHoldingSnapshot }

        for _ in 0..<10 {
            service.walletCore(event: .tokensChanged)
        }
        await source.releaseSnapshot()
        try await waitUntil { await source.contexts.count == 2 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(await source.contexts == [context("account-a"), context("account-a")])
    }

    @Test
    func `a deleted Agent chat leaves the results of an open query at once`() async throws {
        let queryText = "знако"
        let deletedItem = ApiAgentV2ThreadListItem(thread: try makeThread(id: "deleted", title: "Знакомство с TON"))
        let keptItem = ApiAgentV2ThreadListItem(thread: try makeThread(id: "kept", title: "Знакомые адреса"))
        let loader = MutableThreadLoader(items: [deletedItem, keptItem])
        let coordinator = UniversalSearchCoordinator(sources: [
            UniversalSearchAgentConversationSource(loader: { query in await loader.load(query: query) }),
        ])
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context("account-a") },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero)
        )
        let recorder = UpdateRecorder()
        service.add(observer: recorder)
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }
        try await waitUntil { await coordinator.browse().recentDocuments.count == 2 }

        // An open search session keeps the server's matches for its query as a query snapshot
        let querySource = UniversalSearchAgentConversationQuerySource(
            loader: { query in await loader.load(query: query) },
            debounce: .zero
        )
        let query = UniversalSearchQuery(queryText)
        for try await snapshot in querySource.snapshots(for: query, context: context("account-a")) {
            await coordinator.replace(snapshot)
        }
        let openQueryHits = await coordinator.search(queryText).hits.map(\.id.rawValue)
        #expect(Set(openQueryHits) == ["agent-chat:deleted", "agent-chat:kept"])

        await loader.setItems([keptItem])
        service.walletCore(event: .agentThreadDeleted(threadId: "deleted"))

        let deletedID = SearchEntityID("agent-chat:deleted")
        try await waitUntil { recorder.removedIDs == [deletedID] }
        #expect(await coordinator.search(queryText).hits.map(\.id.rawValue) == ["agent-chat:kept"])
        #expect(await coordinator.browse().recentDocuments.map(\.id) == [SearchEntityID("agent-chat:kept")])

        await coordinator.remove(sourceID: querySource.sourceID)
        for try await snapshot in querySource.snapshots(for: query, context: context("account-a")) {
            await coordinator.replace(snapshot)
        }
        #expect(await coordinator.search(queryText).hits.map(\.id.rawValue) == ["agent-chat:kept"])
    }

    @Test
    func `futures sources refresh only when what they index changes`() async throws {
        let catalogue = CountingSource(sourceID: WalletCoreFuturesSearchSource.id, scoping: .global)
        let positions = CountingSource(sourceID: WalletCoreFuturesPositionSearchSource.id, scoping: .account)
        let coordinator = UniversalSearchCoordinator(sources: [catalogue, positions])
        let feed = MarketFeed()
        var client = PerpsClient()
        client.marketSnapshot = { feed.market }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        let service = UniversalSearchIndexService(
            coordinator: coordinator,
            contextProvider: { context("account-a") },
            timing: .init(debounce: .zero, maxPostpone: .zero, loopPacing: .zero),
            perpsStore: store
        )
        service.start()
        service.setWalletReady(true)
        defer { service.stop() }
        try await waitUntil {
            let catalogueCount = await catalogue.count
            let positionsCount = await positions.count
            return catalogueCount == 1 && positionsCount == 1
        }

        try await push(market(["BTC": "97000"], fetchedAt: 1), to: store, feed: feed)
        try await waitUntil { await catalogue.count == 2 }
        try await push(market(["BTC": "98000"], fetchedAt: 2), to: store, feed: feed)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await catalogue.count == 2, "A price change must not refresh the catalogue")
        try await push(market(["BTC": "98000", "ETH": "3000"], fetchedAt: 3), to: store, feed: feed)
        try await waitUntil { await catalogue.count == 3 }

        store.walletCore(event: .updatePerpsPositions(.init(
            accountId: "account-a", snapshot: try accountSnapshot(["BTC"], equity: "10")
        )))
        try await waitUntil { await positions.count == 2 }
        store.walletCore(event: .updatePerpsPositions(.init(
            accountId: "account-a", snapshot: try accountSnapshot(["BTC"], equity: "12")
        )))
        store.walletCore(event: .updatePerpsPositions(.init(
            accountId: "account-b", snapshot: try accountSnapshot(["ETH"], equity: "5")
        )))
        try await Task.sleep(for: .milliseconds(100))
        #expect(await positions.count == 2, "A position's value or another account must not refresh positions")
        store.walletCore(event: .updatePerpsPositions(.init(
            accountId: "account-a", snapshot: try accountSnapshot(["BTC", "ETH"], equity: "12")
        )))
        try await waitUntil { await positions.count == 3 }
        #expect(await catalogue.count == 3)
    }

    @Test
    func `shown futures rows follow their price and position without reindexing`() async throws {
        let feed = MarketFeed()
        var client = PerpsClient()
        client.marketSnapshot = { feed.market }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in },
                               loadDismissedStatuses: { [] }, saveDismissedStatuses: { _ in })
        try await push(market(["BTC": "97000", "ETH": "3000"], fetchedAt: 1), to: store, feed: feed)
        let coordinator = UniversalSearchCoordinator(sources: [])
        try await coordinator.refresh(context: WalletCoreUniversalSearchFactory.currentContext())
        let bitcoinID = WalletCoreFuturesSearchSource.entityID(assetID: "hyperliquid:hl:BTC")
        await coordinator.replace(UniversalSearchSourceSnapshot(
            sourceID: SearchSourceID("test:futures"),
            authority: 100,
            generatedAt: Date(),
            documents: [SearchDocument(id: bitcoinID, kind: .futuresMarket, fields: [.init("BTC", kind: .symbol)])]
        ))
        let resolutions = Counter()
        let presenter = UniversalSearchResultsPresenter { document, _ in
            guard document.id == bitcoinID else { return nil }
            resolutions.value += 1
            let position = store.snapshots["account-a"]?.positions.first { $0.assetId == "hyperliquid:hl:BTC" }
            return UniversalSearchResolvedResult(
                item: UniversalSearchItem(id: bitcoinID.rawValue, content: .chat(UniversalSearchChatResult(
                    title: store.asset(id: "hyperliquid:hl:BTC")?.context.markPx ?? "",
                    subtitle: position?.equity ?? ""
                ))),
                route: .futuresMarket(accountID: "account-a", assetID: "hyperliquid:hl:BTC")
            )
        }
        let screen = UniversalSearchScreenViewController()
        screen.loadViewIfNeeded()
        let results = try #require(screen.children.first as? UniversalSearchViewController)
        let session = UniversalSearchFeatureSession(
            screen: screen, coordinator: coordinator, presenter: presenter, querySources: [], perpsStore: store
        )
        session.start(initialQuery: "btc")
        defer { session.stop() }
        func getRow() -> (price: String, equity: String)? {
            for item in results.sections.flatMap(\.items) where item.id == bitcoinID.rawValue {
                if case .chat(let row) = item.content { return (row.title, row.subtitle) }
            }
            return nil
        }
        try await waitUntil { getRow()?.price == "97000" }

        var count = resolutions.value
        try await push(market(["BTC": "97000", "ETH": "3100"], fetchedAt: 2), to: store, feed: feed)
        try await Task.sleep(for: .milliseconds(100))
        #expect(resolutions.value == count, "A market that is not shown must not refresh the results")
        try await push(market(["BTC": "98000", "ETH": "3100"], fetchedAt: 3), to: store, feed: feed)
        try await waitUntil { getRow()?.price == "98000" }

        count = resolutions.value
        store.walletCore(event: .updatePerpsPositions(.init(
            accountId: "account-b", snapshot: try accountSnapshot(["BTC"], equity: "5")
        )))
        try await Task.sleep(for: .milliseconds(100))
        #expect(resolutions.value == count, "Another account's position must not refresh the results")
        store.walletCore(event: .updatePerpsPositions(.init(
            accountId: "account-a", snapshot: try accountSnapshot(["BTC"], equity: "10")
        )))
        try await waitUntil { getRow()?.equity == "10" }
    }

    private func push(_ market: ApiPerpsMarketSnapshot, to store: PerpsStore, feed: MarketFeed) async throws {
        feed.market = market
        let update = try JSONDecoder().decode(
            ApiUpdate.UpdatePerpsAssets.self,
            from: Data("{\"fetchedAt\":\(market.assetsFetchedAt)}".utf8)
        )
        store.walletCore(event: .updatePerpsAssets(update))
        try await waitUntil { store.market?.assetsFetchedAt == market.assetsFetchedAt }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await condition(), "Search refresh did not make progress")
    }
}

@MainActor
private final class Counter {
    var value = 0
}

@MainActor
private final class MarketFeed {
    var market = ApiPerpsMarketSnapshot(assets: [], assetsFetchedAt: 0)
}

private func market(_ pricesBySymbol: [String: String], fetchedAt: Int64) throws -> ApiPerpsMarketSnapshot {
    let assets: [[String: Any]] = pricesBySymbol.keys.sorted().map { symbol in
        [
            "id": "hyperliquid:hl:\(symbol)",
            "name": symbol,
            "symbol": symbol,
            "dex": "",
            "szDecimals": 4,
            "maxLeverage": 20,
            "context": ["markPx": pricesBySymbol[symbol]!],
        ]
    }
    return try JSONDecoder().decode(
        ApiPerpsMarketSnapshot.self,
        from: JSONSerialization.data(withJSONObject: ["assets": assets, "assetsFetchedAt": fetchedAt])
    )
}

private func accountSnapshot(_ symbols: [String], equity: String) throws -> ApiPerpsAccountSnapshot {
    let positions: [[String: Any]] = symbols.map { symbol in
        [
            "id": symbol,
            "assetId": "hyperliquid:hl:\(symbol)",
            "dex": "",
            "side": "long",
            "collateral": "10",
            "equity": equity,
            "raw": ["leverage": ["value": 5], "positionValue": "50", "unrealizedPnl": "0"],
        ]
    }
    let snapshot: [String: Any] = [
        "positions": positions,
        "totalEquity": equity,
        "totalPnl": "0",
        "timestamp": 0,
        "unavailableDexs": [String](),
    ]
    return try JSONDecoder().decode(
        ApiPerpsAccountSnapshot.self,
        from: JSONSerialization.data(withJSONObject: snapshot)
    )
}

private actor CountingSource: UniversalSearchSource {
    nonisolated let sourceID: SearchSourceID
    nonisolated let scoping: UniversalSearchSourceScoping
    private(set) var count = 0

    init(sourceID: SearchSourceID, scoping: UniversalSearchSourceScoping) {
        self.sourceID = sourceID
        self.scoping = scoping
    }

    func snapshot(for context: UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot {
        count += 1
        return UniversalSearchSourceSnapshot(sourceID: sourceID, generatedAt: Date())
    }
}

@MainActor
private final class Selection {
    var accountID = "account-a"
}

private func context(_ accountID: String) -> UniversalSearchContext {
    UniversalSearchContext(scopeID: accountID, network: "mainnet", localeIdentifier: "en")
}

private func makeThread(id: String, title: String) throws -> ApiAgentV2ThreadSummary {
    let value: [String: Any] = [
        "id": id,
        "revision": 1,
        "createdAt": "2026-10-18T09:00:00Z",
        "updatedAt": "2026-10-18T10:00:00Z",
        "lastActivityAt": "2026-10-18T10:00:00Z",
        "messageCount": 2,
        "title": title,
        "hasCustomTitle": true,
    ]
    return try JSONDecoder().decode(
        ApiAgentV2ThreadSummary.self,
        from: JSONSerialization.data(withJSONObject: value)
    )
}

@MainActor
private final class UpdateRecorder: UniversalSearchIndexServiceObserver {
    private(set) var removedIDs: [SearchEntityID] = []

    func universalSearchIndexService(
        _: UniversalSearchIndexService,
        didUpdate update: UniversalSearchIndexUpdate
    ) {
        if case .documentRemoved(let id) = update.kind {
            removedIDs.append(id)
        }
    }
}

private actor MutableThreadLoader {
    private var items: [ApiAgentV2ThreadListItem]

    init(items: [ApiAgentV2ThreadListItem]) {
        self.items = items
    }

    func setItems(_ items: [ApiAgentV2ThreadListItem]) {
        self.items = items
    }

    func load(query _: String?) -> [ApiAgentV2ThreadListItem] {
        items
    }
}

private actor RecordingSource: UniversalSearchSource {
    nonisolated let sourceID = WalletCoreTokenSearchSource.id
    private(set) var contexts: [UniversalSearchContext] = []
    private let holdsFirstSnapshot: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var isHoldingSnapshot: Bool { continuation != nil }

    init(holdsFirstSnapshot: Bool = false) {
        self.holdsFirstSnapshot = holdsFirstSnapshot
    }

    func releaseSnapshot() {
        continuation?.resume()
        continuation = nil
    }

    func snapshot(for context: UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot {
        contexts.append(context)
        if holdsFirstSnapshot, contexts.count == 1 {
            await withCheckedContinuation { continuation = $0 }
        }
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            generatedAt: Date(),
            documents: [SearchDocument(
                id: SearchEntityID("token:\(context.scopeID ?? "")"),
                kind: .token,
                fields: [SearchField("Token", kind: .title)]
            )]
        )
    }
}
