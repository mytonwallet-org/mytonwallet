import Foundation
import Testing
import WalletContext
import WalletCore
@testable import UIAssets

@Suite @MainActor
struct PerpsHomeAdapterTests {
    @Test func failedRefreshKeepsRecentlyCompleteValuesAndHistoryUndimmed() async throws {
        let snapshot = try cachedSnapshot()
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"btc/1","assetId":"btc","coin":"BTC","oid":1,"time":1000,
         "eventKind":"opened","positionSide":"long","notional":"100","feeToken":"USDC"}
        """.utf8))
        var snapshotFails = false
        var historyFails = false
        var client = PerpsClient()
        client.snapshot = { _ in
            if snapshotFails { throw PerpsError.invalidResponse }
            return snapshot
        }
        client.history = { _ in
            if historyFails { throw PerpsError.invalidResponse }
            return .init(fills: [fill], cashFlows: [])
        }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        snapshotFails = true
        await store.refresh(accountId: "wallet")
        let retained = PerpsHomeAdapter.home(store: store, accountId: "wallet")
        #expect(retained.positions.status == .ready)
        #expect(retained.positions.totalValue == .fromDouble(20, .USD))
        #expect(retained.positions.positions.count == 1)
        #expect(!retained.positions.isStale)
        #expect(retained.positions.positions.allSatisfy { !$0.isStale })
        #expect(retained.marketSections.flatMap(\.tokens).allSatisfy { !$0.isStale })
        #expect(retained.activities.first?.isStale == false)

        snapshotFails = false
        historyFails = true
        await store.refresh(accountId: "wallet")
        let fresh = PerpsHomeAdapter.home(store: store, accountId: "wallet")
        #expect(!fresh.positions.isStale)
        #expect(fresh.positions.totalValue == retained.positions.totalValue)
        #expect(fresh.positions.positions.allSatisfy { !$0.isStale })
        #expect(fresh.marketSections.flatMap(\.tokens).allSatisfy { !$0.isStale })
        #expect(fresh.activities.first?.isStale == false)
    }

    @Test func homeAndSeeAllRetainNormalPricesDuringARefresh() async throws {
        let snapshot = try cachedSnapshot()
        var shouldWait = false
        var response: CheckedContinuation<ApiPerpsSnapshot, Error>?
        var client = PerpsClient()
        client.snapshot = { _ in
            if shouldWait { return try await withCheckedThrowingContinuation { response = $0 } }
            return snapshot
        }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        shouldWait = true
        let refresh = Task { await store.refresh(accountId: "wallet") }
        while response == nil { await Task.yield() }
        for preview in [true, false] {
            let data = PerpsHomeAdapter.home(store: store, accountId: "wallet", previewMarkets: preview)
            #expect(!data.marketSections.isEmpty)
            #expect(data.marketSections.flatMap(\.tokens).allSatisfy { !$0.isStale })
            #expect(!data.positions.isStale)
        }
        response?.resume(throwing: PerpsError.invalidResponse)
        await refresh.value
        #expect(store.snapshotErrors["wallet"] == "PerpsUnavailable")
        #expect(!PerpsHomeAdapter.home(store: store, accountId: "wallet").positions.isStale)
    }

    @Test func legacyCatalogueWithoutFetchTimeRemainsStaleAfterPositionsRefresh() async throws {
        let snapshot = try cachedSnapshot(assetsFetchedAt: nil)
        var client = PerpsClient()
        client.snapshot = { _ in snapshot }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        for preview in [true, false] {
            let data = PerpsHomeAdapter.home(store: store, accountId: "wallet", previewMarkets: preview)
            #expect(!data.marketSections.isEmpty)
            #expect(data.marketSections.flatMap(\.tokens).allSatisfy { $0.isStale })
            #expect(!data.positions.isStale)
        }
    }

    @Test func partialInitialSnapshotShowsKnownPositionsWithoutInventingPortfolioTotals() async throws {
        var snapshot = try cachedSnapshot()
        snapshot.unavailableDexs = ["xyz"]
        var client = PerpsClient()
        client.snapshot = { _ in snapshot }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let data = PerpsHomeAdapter.positions(store: store, accountId: "wallet")
        #expect(data.status == .ready)
        #expect(data.isStale)
        #expect(data.positions.count == 1)
        #expect(data.totalValue.optionalAmount == nil)
        #expect(data.profitLoss.text == "—")
    }

    @Test func anInitialFailureKeepsTheRetryState() async {
        var client = PerpsClient()
        client.snapshot = { _ in throw PerpsError.invalidResponse }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let data = PerpsHomeAdapter.positions(store: store, accountId: "wallet")
        guard case .unavailable = data.status else { Issue.record("Expected retryable initial failure"); return }
        #expect(data.totalValue.optionalAmount == nil)
        #expect(data.positions.isEmpty)
    }

    private func cachedSnapshot(assetsFetchedAt: Int64? = Int64(Date.now.timeIntervalSince1970 * 1_000)) throws -> ApiPerpsSnapshot {
        var snapshot = try JSONDecoder().decode(ApiPerpsSnapshot.self, from: Data("""
        {"assets":[{"id":"btc","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
          "dex":"","szDecimals":2,"maxLeverage":40,"context":{"markPx":"84","prevDayPx":"100"}}],
         "positions":[{"id":"wallet/btc","assetId":"btc","dex":"","side":"long","collateral":"100",
          "equity":"20","isNearLiquidation":true,"returnOnEquity":"-0.8","raw":{"coin":"BTC","entryPx":"100","liquidationPx":"80",
           "leverage":{"type":"isolated","value":5},"marginUsed":"20","positionValue":"420",
           "returnOnEquity":"-0.8","szi":"5","unrealizedPnl":"-80"}}],
         "totalEquity":"20","totalPnl":"-80","totalReturnOnEquity":"-0.8","timestamp":0,"unavailableDexs":[]}
        """.utf8))
        snapshot.assetsFetchedAt = assetsFetchedAt
        return snapshot
    }

    @Test func backendSectionsOwnOrderLayoutsLimitsNamesAndChartSelection() async throws {
        let assets = (0..<10).map { index -> [String: Any] in
            ["id": "asset-\(index)", "name": "xyz:TOKEN\(index)", "symbol": "TOKEN\(index)",
             "displayName": "Company \(index)", "keywords": ["rwa", "stock"], "label": "Issuer", "tintColor": "#1BB0CA",
             "chain": "hyperliquid", "provider": "hyperliquid", "dex": "xyz", "szDecimals": 2, "maxLeverage": 10,
             "context": ["markPx": "100", "prevDayPx": "105", "percentChange24h": -5, "dayNtlVlm": "\(index * 100)"]]
        }
        let section: (String, String, Int, [[String: Any]]) -> [String: Any] = { id, layout, limit, values in
            ["id": id, "title": "Backend \(id)", "layout": layout, "mobileLimit": limit, "desktopLimit": 12,
             "hasMore": false, "assets": values]
        }
        var client = PerpsClient()
        client.snapshot = { _ in
            try JSONDecoder().decode(ApiPerpsSnapshot.self, from: JSONSerialization.data(withJSONObject: [
                "assets": assets, "positions": [], "totalEquity": "0", "totalPnl": "0", "timestamp": 0, "unavailableDexs": [],
                "marketSections": [section("stocks", "grid", 8, assets), section("indices", "grid", 4, assets),
                                   section("gold", "rows", 1, [assets[0]]),
                                   section("editorial", "largeHorizontal", 1, [assets[0], assets[1]])],
            ]))
        }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let sections = PerpsHomeAdapter.home(store: store, accountId: "wallet", charts: ["asset-0": [[0, 100], [1, 110]]]).marketSections
        #expect(sections.map(\.id) == ["stocks", "indices", "gold", "editorial"])
        #expect(sections.map(\.tokens.count) == [8, 4, 1, 1])
        #expect(sections.map(\.layout) == [.grid, .grid, .rows, .largeHorizontal])
        #expect(sections.flatMap(\.tokens).allSatisfy { !$0.showsChain })
        #expect(sections[0].title == "Backend stocks")
        #expect(sections[0].showsSeeAll)
        #expect(!sections[2].showsSeeAll)
        #expect(sections[0].tokens[0].name == "Company 0")
        #expect(sections[0].tokens[0].token.isRwaStock)
        #expect(sections[0].tokens[0].token.label == "Issuer")
        #expect(sections[3].tokens[0].chart == .sparkline(points: [1, 0], tint: 0x1BB0CA))
        #expect(!sections[3].tokens[0].isPositive)
        #expect(PerpsHomeAdapter.featuredAssets(store.snapshots["wallet"]).map(\.id) == ["asset-0"])
        #expect(PerpsHomeAdapter.home(store: store, accountId: "wallet", previewMarkets: false).marketSections[0].tokens.count == 10)
    }

    @Test func explicitlyEmptyBackendSectionsDoNotRestoreLegacyGroups() async throws {
        var client = PerpsClient()
        client.snapshot = { _ in
            try JSONDecoder().decode(ApiPerpsSnapshot.self, from: Data("""
            {"assets":[{"id":"btc","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
              "dex":"","szDecimals":2,"maxLeverage":40,"context":{"markPx":"100","prevDayPx":"100"}}],
             "positions":[],"totalEquity":"0","totalPnl":"0","timestamp":0,"unavailableDexs":[],"marketSections":[]}
            """.utf8))
        }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        #expect(PerpsHomeAdapter.home(store: store, accountId: "wallet").marketSections.isEmpty)
        #expect(PerpsHomeAdapter.featuredAssets(store.snapshots["wallet"]).isEmpty)
    }

    @Test func livePositionUsesSdkPercentageAndLiquidationWarning() async throws {
        var client = PerpsClient()
        client.snapshot = { _ in
            try JSONDecoder().decode(ApiPerpsSnapshot.self, from: Data("""
            {"assets":[{"id":"btc","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
              "dex":"","szDecimals":2,"maxLeverage":40,"context":{"markPx":"84","prevDayPx":"100"}}],
             "positions":[{"id":"wallet/btc","assetId":"btc","dex":"","side":"long","collateral":"100",
              "equity":"20","isNearLiquidation":true,"returnOnEquity":"-0.8","raw":{"coin":"BTC","entryPx":"100","liquidationPx":"80",
               "leverage":{"type":"isolated","value":5},"marginUsed":"20","positionValue":"420",
               "returnOnEquity":"-0.8","szi":"5","unrealizedPnl":"-80"}}],
             "totalEquity":"20","totalPnl":"-80","totalReturnOnEquity":"-0.8","timestamp":0,"unavailableDexs":[]}
            """.utf8))
        }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let data = PerpsHomeAdapter.positions(store: store, accountId: "wallet")
        let row = try #require(data.positions.first)
        #expect(row.directionAndLeverage == "Long 5x")
        #expect(row.isAtRisk)
        #expect(row.profitLoss.text.contains("80 (80.0%)"))
        #expect(data.profitLoss.text.contains(" · " + formatPercent(-0.8, showPlus: false, showMinus: false)))
    }

    @Test func featuredMarketsUseLiveVolumeAndChartsWithoutTruncatingFullLists() async throws {
        let assets = try (0..<9).map { index in
            try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
            {"id":"asset-\(index)","name":"TOKEN\(index)","symbol":"TOKEN\(index)","chain":"hyperliquid",
             "provider":"hyperliquid","dex":"","szDecimals":2,"maxLeverage":10,"isDelisted":\(index == 8),
             "context":{"markPx":"100","prevDayPx":"95","percentChange24h":5,"dayNtlVlm":"\(index * 100)"}}
            """.utf8))
        }
        var client = PerpsClient()
        client.snapshot = { _ in
            try JSONDecoder().decode(ApiPerpsSnapshot.self, from: JSONSerialization.data(withJSONObject: [
                "assets": JSONSerialization.jsonObject(with: JSONEncoder().encode(assets)), "positions": [],
                "totalEquity": "0", "totalPnl": "0", "timestamp": 0, "unavailableDexs": [],
            ]))
        }
        client.history = { _ in .init(fills: [], cashFlows: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let data = PerpsHomeAdapter.home(store: store, accountId: "wallet", charts: ["asset-7": [[0, 100], [1, 110]]])
        #expect(data.marketSections.flatMap(\.tokens).allSatisfy { !$0.showsChain })
        let featured = try #require(data.marketSections.first)
        #expect(featured.layout == .largeHorizontal)
        #expect(featured.tokens.map(\.id) == ["asset-7", "asset-6", "asset-5", "asset-4", "asset-3", "asset-2"])
        #expect(featured.tokens.first?.chart == .sparkline(points: [1, 0], tint: 0x2C92F0))
        #expect(data.marketSections.last?.tokens.count == 5)
        #expect(PerpsHomeAdapter.home(store: store, accountId: "wallet", previewMarkets: false).marketSections.last?.tokens.count == 8)
        #expect(PerpsHomeAdapter.home(store: store, accountId: "other-wallet").marketSections.isEmpty)
    }
}
