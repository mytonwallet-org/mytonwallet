import Dependencies
import Foundation
import Testing
import UIComponents
import UIKit
import WalletContext
import WalletCore
@testable import UIAssets

@Suite @MainActor
struct PerpsHomeAdapterTests {
    @Test(arguments: [false, true])
    func keepHeroWhenPositionMetadataIsMissing(isCatalogueUnavailable: Bool) async throws {
        try await withDependencies { $0.context = .live } operation: {
            let snapshot = try account()
            var emptyMarket = try market()
            emptyMarket.assets = []
            emptyMarket.marketSections = []
            var client = try client()
            client.marketSnapshot = {
                if isCatalogueUnavailable { throw PerpsError.invalidResponse }
                return emptyMarket
            }
            client.positions = { _ in snapshot }
            let store = PerpsStore(client: client, load: { [] }, save: { _ in })
            await store.refresh(accountId: "wallet")
            let data = PerpsHomeAdapter.home(store: store, accountId: "wallet")
            #expect(data.positions.status == .ready)
            #expect(data.positions.positions.isEmpty)
            #expect(data.positions.totalValue == .fromDouble(20, .USD))
            let controller = PerpsHomeVC(data: data, onAction: { _ in })
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            controller.view.layoutIfNeeded()
            let collection = try #require(controller.view.subviews.compactMap { $0 as? UICollectionView }.first)
            let hasHero = collection.visibleCells.contains { $0 is PerpsPositionsSummaryCell }
            #expect(hasHero)

            store.walletCore(event: .updatePerpsPositions(.init(accountId: "wallet", snapshot: try account(positions: false))))
            controller.update(data: PerpsHomeAdapter.home(store: store, accountId: "wallet"))
            controller.view.layoutIfNeeded()
            #expect(collection.numberOfSections == 0)
        }
    }

    @Test func failedRefreshKeepsRecentlyCompleteValuesAndHistoryUndimmed() async throws {
        let snapshot = try account()
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"btc/1","assetId":"btc","coin":"BTC","oid":1,"time":1000,
         "eventKind":"opened","positionSide":"long","notional":"100","feeToken":"USDC"}
        """.utf8))
        var snapshotFails = false
        var historyFails = false
        var client = try client()
        client.positions = { _ in
            if snapshotFails { throw PerpsError.invalidResponse }
            return snapshot
        }
        client.history = { _ in
            if historyFails { throw PerpsError.invalidResponse }
            return .init(fills: [fill])
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
        #expect(!store.isMarketStale())
        #expect(retained.activities.count == 1)
        #expect(!store.isHistoryStale(accountId: "wallet"))

        snapshotFails = false
        historyFails = true
        await store.refresh(accountId: "wallet")
        let fresh = PerpsHomeAdapter.home(store: store, accountId: "wallet")
        #expect(!fresh.positions.isStale)
        #expect(fresh.positions.totalValue == retained.positions.totalValue)
        #expect(!store.isMarketStale())
        #expect(fresh.activities.count == 1)
        #expect(!store.isHistoryStale(accountId: "wallet"))
    }

    @Test func homeAndSeeAllRetainNormalPricesDuringARefresh() async throws {
        let snapshot = try account()
        var shouldWait = false
        var response: CheckedContinuation<ApiPerpsAccountSnapshot, Error>?
        var client = try client()
        client.positions = { _ in
            if shouldWait { return try await withCheckedThrowingContinuation { response = $0 } }
            return snapshot
        }
        client.history = { _ in .init(fills: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        shouldWait = true
        let refresh = Task { await store.refresh(accountId: "wallet") }
        while response == nil { await Task.yield() }
        for preview in [true, false] {
            let data = PerpsHomeAdapter.home(store: store, accountId: "wallet", previewMarkets: preview)
            #expect(!data.marketSections.isEmpty)
            #expect(!data.positions.isStale)
        }
        #expect(!store.isMarketStale())
        response?.resume(throwing: PerpsError.invalidResponse)
        await refresh.value
        #expect(store.snapshotErrors["wallet"] == "PerpsUnavailable")
        #expect(!PerpsHomeAdapter.home(store: store, accountId: "wallet").positions.isStale)
    }

    @Test func partialInitialSnapshotShowsKnownPositionsWithoutInventingPortfolioTotals() async throws {
        var snapshot = try account()
        snapshot.unavailableDexs = ["xyz"]
        var client = try client()
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let data = PerpsHomeAdapter.positions(store: store, accountId: "wallet")
        #expect(data.status == .ready)
        #expect(data.isStale)
        #expect(data.positions.count == 1)
        #expect(data.totalValue.optionalAmount == nil)
        #expect(data.profitLoss.text == "—")
    }

    @Test func anInitialFailureKeepsTheRetryState() async throws {
        var client = try client()
        client.positions = { _ in throw PerpsError.invalidResponse }
        client.history = { _ in .init(fills: []) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let data = PerpsHomeAdapter.positions(store: store, accountId: "wallet")
        guard case .unavailable = data.status else { Issue.record("Expected retryable initial failure"); return }
        #expect(data.totalValue.optionalAmount == nil)
        #expect(data.positions.isEmpty)
    }

    private func market() throws -> ApiPerpsMarketSnapshot {
        try JSONDecoder().decode(ApiPerpsMarketSnapshot.self, from: Data("""
        {"assets":[{"id":"btc","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
          "dex":"","szDecimals":2,"maxLeverage":40,"context":{"markPx":"84","prevDayPx":"100"}}],
         "marketSections":[{"id":"popular","title":"Popular","layout":"grid","mobileLimit":8,"hasMore":false,
          "assets":[{"id":"btc","name":"BTC","symbol":"BTC","dex":"","szDecimals":2,"maxLeverage":40,"context":{"markPx":"84"}}]}],
         "assetsFetchedAt":\(Int64(Date.now.timeIntervalSince1970 * 1_000))}
        """.utf8))
    }

    private func account(positions: Bool = true) throws -> ApiPerpsAccountSnapshot {
        let position = """
        {"id":"wallet/btc","assetId":"btc","dex":"","side":"long","collateral":"100",
         "equity":"20","isNearLiquidation":true,"returnOnEquity":"-0.8","raw":{"coin":"BTC","entryPx":"100","liquidationPx":"80",
          "leverage":{"type":"isolated","value":5},"marginUsed":"20","positionValue":"420",
          "returnOnEquity":"-0.8","szi":"5","unrealizedPnl":"-80"}}
        """
        let totals = positions ? #""totalEquity":"20","totalPnl":"-80","totalReturnOnEquity":"-0.8""#
            : #""totalEquity":"0","totalPnl":"0""#
        return try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("""
        {"positions":[\(positions ? position : "")],\(totals),
         "timestamp":\(Int64(Date.now.timeIntervalSince1970 * 1_000)),"unavailableDexs":[]}
        """.utf8))
    }

    private func withdrawableAccount(balance: Bool = true, canSign: Bool = true) throws -> ApiPerpsAccountSnapshot {
        let preview = #","balanceWithdrawal":{"balance":"1.5","amount":"1.47","bridgeFee":"0.2","receiveAmount":"1.27"}"#
        return try JSONDecoder().decode(ApiPerpsAccountSnapshot.self, from: Data("""
        {"tradingAvailability":{"isAvailable":\(canSign)},"positions":[],"totalEquity":"0","totalPnl":"0",
         "timestamp":\(Int64(Date.now.timeIntervalSince1970 * 1_000)),"unavailableDexs":[]\(balance ? preview : "")}
        """.utf8))
    }

    @Test func balanceRowShowsTheRawBalanceAndWhatArrivesAfterFees() async throws {
        let snapshot = try withdrawableAccount()
        var client = try client()
        client.positions = { _ in snapshot }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let row = try #require(PerpsHomeAdapter.home(store: store, accountId: "wallet").balanceWithdrawal)
        #expect(row.balance == PerpsFormatting.money("1.5"))
        #expect(row.token.symbol == "USDC")
        #expect(!row.isPreparing)
    }

    @Test func balanceRowNeedsAnOffer() async throws {
        let snapshot = try withdrawableAccount(balance: false)
        var client = try client()
        client.positions = { _ in snapshot }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        #expect(PerpsHomeAdapter.home(store: store, accountId: "wallet").balanceWithdrawal == nil)
    }

    /// A view account sees its balance, and cannot act on it.
    @Test(arguments: [true, false])
    func balanceRowCanWithdrawOnlyForAnAccountThatCanSign(_ canSign: Bool) async throws {
        let snapshot = try withdrawableAccount(canSign: canSign)
        var client = try client()
        client.positions = { _ in snapshot }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let row = try #require(PerpsHomeAdapter.home(store: store, accountId: "wallet").balanceWithdrawal)
        #expect(row.canWithdraw == canSign)
    }

    @Test func aCompletedWithdrawalKeepsAnAccountNewToFutures() async throws {
        let snapshot = try account(positions: false)
        var client = try client()
        client.positions = { _ in snapshot }
        var withdrawal = ApiPerpsOperation(id: "withdrawal", accountId: "wallet", assetId: "USDC", kind: "withdraw", createdAt: 0)
        withdrawal.state = "completed"
        var trade = ApiPerpsOperation(id: "trade", accountId: "wallet", assetId: "btc", kind: "close", createdAt: 0)
        trade.state = "completed"
        let onlyWithdrew = PerpsStore(client: client, load: { [withdrawal] }, save: { _ in })
        await onlyWithdrew.refresh(accountId: "wallet")
        #expect(PerpsHomeAdapter.showsOnboarding(store: onlyWithdrew, accountId: "wallet"))
        let traded = PerpsStore(client: client, load: { [withdrawal, trade] }, save: { _ in })
        await traded.refresh(accountId: "wallet")
        #expect(!PerpsHomeAdapter.showsOnboarding(store: traded, accountId: "wallet"))
    }

    @Test(arguments: [nil, "older"])
    func failedOrdersJoinTradesInTimeOrder(nextCursor: String?) async throws {
        let fills = try [3000, 1000].map { time in
            try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
            {"activityId":"btc/\(time)","coin":"BTC","oid":\(time),"time":\(time),"eventKind":"opened",
             "positionSide":"long","notional":"100","feeToken":"USDC"}
            """.utf8))
        }
        var client = try client()
        client.history = { _ in .init(fills: fills, nextCursor: nextCursor) }
        func operation(_ id: String, kind: String = "reduce", assetId: String = "btc", createdAt: Int64,
                       stage: String = "finished") -> ApiPerpsOperation {
            var operation = ApiPerpsOperation(id: id, accountId: "wallet", assetId: assetId, kind: kind, createdAt: createdAt)
            operation.state = "failed"
            operation.stage = stage
            operation.error = "PerpsInsufficientMargin"
            return operation
        }
        let saved = [
            operation("failed", createdAt: 2000),
            operation("beforeLoadedTrades", createdAt: 500),
            operation("neverSubmitted", kind: "open", createdAt: 2500, stage: "preparing"),
            operation("withdrawal", kind: "withdraw", assetId: "USDC", createdAt: 2600),
        ]
        let store = PerpsStore(client: client, load: { saved }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let activities = PerpsHomeAdapter.home(store: store, accountId: "wallet").activities
        let failedIDs = activities.compactMap { PerpsTradeActivity.failedOrderOperationID(activityID: $0.id) }
        #expect(activities.map(\.isFailed) == (nextCursor == nil ? [false, true, false, true] : [false, true, false]))
        #expect(failedIDs == (nextCursor == nil ? ["failed", "beforeLoadedTrades"] : ["failed"]))
        #expect(activities[1].amount.text == lang("Failed"))
        #expect(activities[1].amount.tone == .negative)
        #expect(activities[1].title == lang("Reduce Position") + " · BTC")
    }

    private func client() throws -> PerpsClient {
        let market = try market()
        var client = PerpsClient()
        client.marketSnapshot = { market }
        client.positions = { _ in throw PerpsError.invalidResponse }
        client.history = { _ in .init(fills: []) }
        return client
    }

    @Test func cachedPositionsActivityAndMarketsRenderBeforeTheSDKAnswers() async throws {
        let directory = URL.temporaryDirectory.appending(components: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fill = try JSONDecoder().decode(ApiPerpsFill.self, from: Data("""
        {"activityId":"btc/1","coin":"BTC","oid":1,"time":1000,"eventKind":"opened","positionSide":"long","notional":"100","feeToken":"USDC"}
        """.utf8))
        let snapshot = try account()
        var client = try client()
        client.positions = { _ in snapshot }
        client.history = { _ in .init(fills: [fill]) }
        await PerpsStore(client: client, cacheDirectory: directory, load: { [] }, save: { _ in }).refresh(accountId: "wallet")
        var offline = PerpsClient()
        offline.marketSnapshot = { Issue.record("Cached markets must render without the SDK"); throw PerpsError.invalidResponse }
        offline.positions = { _ in Issue.record("Cached positions must render without the SDK"); throw PerpsError.invalidResponse }
        offline.history = { _ in Issue.record("Cached Activity must render without the SDK"); throw PerpsError.invalidResponse }
        let restored = PerpsStore(client: offline, cacheDirectory: directory, load: { [] }, save: { _ in })
        await restored.loadFromCache(accountIds: ["wallet", "other"])
        let home = PerpsHomeAdapter.home(store: restored, accountId: "wallet")
        #expect(home.positions.status == .ready)
        #expect(home.positions.positions.map(\.id) == ["wallet/btc"])
        #expect(home.positions.totalValue == .fromDouble(20, .USD))
        #expect(!home.positions.isStale)
        #expect(home.marketSections.map(\.id) == ["popular"])
        #expect(home.activities.map(\.id) == ["btc/1"])
        let other = PerpsHomeAdapter.positions(store: restored, accountId: "other")
        #expect(other.status == .loading)
        #expect(other.positions.isEmpty)
    }

    @Test func pushedPositionsRenderOnlyForTheirAccount() async throws {
        let store = PerpsStore(client: try client(), load: { [] }, save: { _ in })
        await store.refresh(accountId: "other")
        store.walletCore(event: .updatePerpsPositions(.init(accountId: "wallet", snapshot: try account())))
        #expect(PerpsHomeAdapter.positions(store: store, accountId: "wallet").positions.count == 1)
        let other = PerpsHomeAdapter.positions(store: store, accountId: "other")
        #expect(other.accountID == "other")
        #expect(other.positions.isEmpty)
        store.walletCore(event: .updatePerpsPositions(.init(accountId: "other", snapshot: try account(positions: false))))
        #expect(PerpsHomeAdapter.positions(store: store, accountId: "other").status == .ready)
        #expect(PerpsHomeAdapter.positions(store: store, accountId: "wallet").positions.count == 1)
    }

    @Test func backendSectionsOwnOrderLayoutsLimitsNamesAndChartSelection() async throws {
        let assets = (0..<10).map { index -> [String: Any] in
            ["id": "asset-\(index)", "name": "xyz:TOKEN\(index)", "symbol": "TOKEN\(index)", "sparkline": [100, 110],
             "displayName": "Company \(index)", "keywords": ["rwa", "stock"], "label": "Issuer", "tintColor": "#1BB0CA",
             "chain": "hyperliquid", "provider": "hyperliquid", "dex": "xyz", "szDecimals": 2, "maxLeverage": 10,
             "context": ["markPx": "100", "prevDayPx": "105", "percentChange24h": -5, "dayNtlVlm": "\(index * 100)"]]
        }
        let section: (String, String, Int, [[String: Any]]) -> [String: Any] = { id, layout, limit, values in
            ["id": id, "title": "Backend \(id)", "layout": layout, "mobileLimit": limit, "desktopLimit": 12,
             "hasMore": false, "assets": values]
        }
        var client = try client()
        client.marketSnapshot = {
            try JSONDecoder().decode(ApiPerpsMarketSnapshot.self, from: JSONSerialization.data(withJSONObject: [
                "assets": assets, "assetsFetchedAt": 0,
                "marketSections": [section("stocks", "grid", 8, assets), section("indices", "grid", 4, assets),
                                   section("gold", "rows", 1, [assets[0]]),
                                   section("editorial", "largeHorizontal", 1, [assets[0], assets[1]]),
                                   ["id": "all", "title": "All", "layout": "grid", "desktopLimit": 12, "hasMore": false, "assets": assets]],
            ]))
        }
        client.positions = { _ in try self.account(positions: false) }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let sections = PerpsHomeAdapter.home(store: store, accountId: "wallet").marketSections
        #expect(sections.map(\.id) == ["stocks", "indices", "gold", "editorial", "all"])
        #expect(sections.map(\.tokens.count) == [8, 4, 1, 1, 8])
        #expect(sections.map(\.layout) == [.grid, .grid, .rows, .largeHorizontal, .grid])
        #expect(sections.flatMap(\.tokens).allSatisfy { !$0.showsChain })
        #expect(sections[0].title == "Backend stocks")
        #expect(sections[0].showsSeeAll)
        #expect(!sections[2].showsSeeAll)
        #expect(sections[0].tokens[0].name == "Company 0")
        #expect(sections[0].tokens[0].token.isRwaStock)
        #expect(sections[0].tokens[0].token.label == "Issuer")
        #expect(sections[3].tokens[0].chart == .sparkline(points: [1, 0], tint: 0x1BB0CA))
        #expect(sections[0].tokens[0].chart == nil)
        #expect(!sections[3].tokens[0].isPositive)
        #expect(sections[4].showsSeeAll)
        #expect(PerpsHomeAdapter.home(store: store, accountId: "wallet", previewMarkets: false).marketSections[0].tokens.count == 10)
    }

    @Test func livePositionUsesSdkPercentageAndLiquidationWarning() async throws {
        let snapshot = try account()
        var client = try client()
        client.positions = { _ in snapshot }
        let store = PerpsStore(client: client, load: { [] }, save: { _ in })
        await store.refresh(accountId: "wallet")
        let data = PerpsHomeAdapter.positions(store: store, accountId: "wallet")
        let row = try #require(data.positions.first)
        #expect(row.directionAndLeverage == "Long 5x")
        #expect(row.isAtRisk)
        #expect(row.profitLoss.text.contains("80 (80.0%)"))
        #expect(data.profitLoss.text.contains(" · " + formatPercent(-0.8, showPlus: false, showMinus: false)))
    }
}
