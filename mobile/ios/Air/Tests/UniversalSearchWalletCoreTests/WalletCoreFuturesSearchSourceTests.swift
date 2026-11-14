import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletCore

@Suite("WalletCore Universal Search futures sources")
struct WalletCoreFuturesSearchSourceTests {
    @Test
    func `catalogue documents index names tickers and keywords without market data`() throws {
        let market = try makeMarket(assets: [
            makeAsset(id: "hyperliquid:xyz:TSLA", symbol: "TSLA", displayName: "Tesla", keywords: ["rwa", "stock"]),
            makeAsset(id: "hyperliquid:hl:kPEPE", symbol: "kPEPE"),
        ])

        let documents = WalletCoreFuturesSearchSource.documents(
            entries: WalletCoreFuturesSearchSource.entries(market: market)
        )
        let tesla = try #require(documents.first {
            $0.id == WalletCoreFuturesSearchSource.entityID(assetID: "hyperliquid:xyz:TSLA")
        })
        let pepe = try #require(documents.first {
            $0.id == WalletCoreFuturesSearchSource.entityID(assetID: "hyperliquid:hl:kPEPE")
        })

        #expect(tesla.kind == .futuresMarket)
        #expect(tesla.fields == [
            SearchField("Tesla", kind: .title),
            SearchField("TSLA", kind: .symbol),
            SearchField("rwa", kind: .keyword),
            SearchField("stock", kind: .keyword),
        ])
        #expect(tesla.attributeValue(for: WalletCoreSearchAttributeKey.futuresAssetID) == "hyperliquid:xyz:TSLA")
        #expect(tesla.signals == SearchSignals())
        #expect(pepe.fields == [SearchField("kPEPE", kind: .symbol)])
    }

    @Test
    func `a catalogue push that only moves prices leaves the snapshot unchanged`() async throws {
        let before = try makeMarket(assets: [makeAsset(id: "hyperliquid:hl:BTC", symbol: "BTC", markPx: "97000")])
        let after = try makeMarket(
            assets: [makeAsset(id: "hyperliquid:hl:BTC", symbol: "BTC", markPx: "98000", change: 4.2)],
            fetchedAt: 60_000
        )

        #expect(WalletCoreFuturesSearchSource.entries(market: before) == WalletCoreFuturesSearchSource.entries(market: after))
        let context = UniversalSearchContext(scopeID: "account", network: "mainnet", localeIdentifier: "en")
        let date = Date(timeIntervalSince1970: 1)
        let first = try await WalletCoreFuturesSearchSource(
            loader: { WalletCoreFuturesSearchSource.entries(market: before) },
            clock: { date }
        ).snapshot(for: context)
        let second = try await WalletCoreFuturesSearchSource(
            loader: { WalletCoreFuturesSearchSource.entries(market: after) },
            clock: { date }
        ).snapshot(for: context)
        #expect(first == second)
    }

    @Test
    func `positions mark only the markets the account holds`() async throws {
        let snapshot = try makeAccountSnapshot(assetIDs: ["hyperliquid:hl:SOL", "hyperliquid:hl:BTC"])
        let source = WalletCoreFuturesPositionSearchSource(loader: { accountID in
            accountID == "account-a" ? WalletCoreFuturesPositionSearchSource.heldAssetIDs(snapshot) : []
        })

        let held = try await source.snapshot(for: context("account-a"))
        let empty = try await source.snapshot(for: context("account-b"))

        #expect(held.documents.isEmpty)
        #expect(held.signalContributions.map(\.entityID) == [
            WalletCoreFuturesSearchSource.entityID(assetID: "hyperliquid:hl:BTC"),
            WalletCoreFuturesSearchSource.entityID(assetID: "hyperliquid:hl:SOL"),
        ])
        #expect(held.signalContributions.allSatisfy { $0.signals.traits == .held })
        #expect(empty.signalContributions.isEmpty)
    }

    private func context(_ accountID: String) -> UniversalSearchContext {
        UniversalSearchContext(scopeID: accountID, network: "mainnet", localeIdentifier: "en")
    }
}

private func makeAsset(
    id: String,
    symbol: String,
    displayName: String? = nil,
    keywords: [String]? = nil,
    markPx: String = "1",
    change: Double? = nil
) -> [String: Any] {
    var asset: [String: Any] = [
        "id": id,
        "name": symbol,
        "symbol": symbol,
        "dex": "",
        "szDecimals": 4,
        "maxLeverage": 20,
    ]
    var context: [String: Any] = ["markPx": markPx]
    context["percentChange24h"] = change
    asset["context"] = context
    asset["displayName"] = displayName
    asset["keywords"] = keywords
    return asset
}

private func makeMarket(assets: [[String: Any]], fetchedAt: Int64 = 0) throws -> ApiPerpsMarketSnapshot {
    try JSONDecoder().decode(
        ApiPerpsMarketSnapshot.self,
        from: JSONSerialization.data(withJSONObject: ["assets": assets, "assetsFetchedAt": fetchedAt])
    )
}

private func makeAccountSnapshot(assetIDs: [String], equity: String = "10") throws -> ApiPerpsAccountSnapshot {
    let positions: [[String: Any]] = assetIDs.map { assetID in
        [
            "id": assetID,
            "assetId": assetID,
            "dex": "",
            "side": "long",
            "collateral": "10",
            "equity": equity,
            "raw": [
                "leverage": ["value": 5],
                "positionValue": "50",
                "unrealizedPnl": "0",
            ],
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
