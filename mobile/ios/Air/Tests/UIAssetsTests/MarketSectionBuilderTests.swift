import Foundation
import Testing
@testable import UIAssets
import WalletCore

@Suite("Market Sections")
struct MarketSectionBuilderTests {
    @Test
    func `uses backend localization and exposes the full show all list`() throws {
        let response = try makeResponse(
            title: "Популярные токены",
            limit: 2,
            hasMore: false,
            assetCount: 3
        )

        let section = try #require(
            MarketSectionBuilder.build(from: response, storeTokens: [:]).first
        )

        #expect(section.title == "Популярные токены")
        #expect(section.tokens.count == 3)
        #expect(section.visibleTokens(columnCount: 4).count == 2)
        #expect(section.visibleTokens(columnCount: 6).count == 2)
        #expect(section.showsSeeAll(columnCount: 4))
    }

    @Test
    func `adapts the preview to its width without discarding the full list`() throws {
        let response = try makeResponse(
            title: "Popular Tokens",
            limit: nil,
            mobileLimit: 8,
            desktopLimit: 12,
            hasMore: false,
            assetCount: 12
        )

        let section = try #require(
            MarketSectionBuilder.build(from: response, storeTokens: [:]).first
        )

        for (width, expectedColumns) in [(390.0, 4), (479, 4), (480, 5), (567, 5), (568, 6), (900, 6), (390, 4)] {
            let columns = MarketGridLayout.columnCount(availableWidth: width)
            #expect(columns == expectedColumns)
            #expect(section.visibleTokens(columnCount: columns).map(\.id) == (0..<(expectedColumns * 2)).map { "asset-\($0)" })
            #expect(section.showsSeeAll(columnCount: columns) == (expectedColumns < 6))
            #expect(section.tokens.count == 12)
        }
    }

    @Test
    func `caps grids without backend limits to two rows`() throws {
        let response = try makeResponse(title: "Tokens", limit: nil, hasMore: false, assetCount: 30)
        let section = try #require(MarketSectionBuilder.build(from: response, storeTokens: [:]).first)

        for columns in 4...6 {
            #expect(section.visibleTokens(columnCount: columns).count == columns * 2)
            #expect(section.showsSeeAll(columnCount: columns))
        }
        #expect(section.tokens.count == 30)
    }

    @Test
    func `respects smaller backend limits and falls back to the available limit`() throws {
        for (mobile, desktop, narrowCount, wideCount) in [
            (Optional(6), Optional(9), 6, 9),
            (6, nil, 6, 6),
            (nil, 9, 8, 9),
        ] {
            let response = try makeResponse(
                title: "Tokens", limit: nil, mobileLimit: mobile, desktopLimit: desktop,
                hasMore: false, assetCount: 14
            )
            let section = try #require(MarketSectionBuilder.build(from: response, storeTokens: [:]).first)
            #expect(section.visibleTokens(columnCount: 4).count == narrowCount)
            #expect(section.visibleTokens(columnCount: 6).count == wideCount)
        }
    }

    @Test(arguments: [false, true])
    func `keeps short sections intact and honors backend hasMore`(hasMore: Bool) throws {
        let response = try makeResponse(
            title: "Tokens", limit: nil, mobileLimit: 8, desktopLimit: 12,
            hasMore: hasMore, assetCount: 7
        )
        let section = try #require(MarketSectionBuilder.build(from: response, storeTokens: [:]).first)
        for columns in 4...6 {
            #expect(section.visibleTokens(columnCount: columns).count == 7)
            #expect(section.showsSeeAll(columnCount: columns) == hasMore)
        }
    }

    @Test(arguments: ["largeHorizontal", "rows"])
    func `does not apply grid capacity to other layouts`(layout: String) throws {
        let response = try makeResponse(title: "Tokens", limit: nil, hasMore: false, assetCount: 14, layout: layout)
        let section = try #require(MarketSectionBuilder.build(from: response, storeTokens: [:]).first)
        for columns in 4...6 {
            #expect(section.visibleTokens(columnCount: columns).count == 14)
            #expect(!section.showsSeeAll(columnCount: columns))
        }
    }

    @Test
    func `builds normalized backend sparklines`() throws {
        let response = try makeResponse(
            title: "Today's Movers",
            limit: nil,
            hasMore: false,
            assetCount: 1,
            sparkline: [10, 20, 15],
            tintColor: "#123456"
        )
        let section = try #require(
            MarketSectionBuilder.build(from: response, storeTokens: [:]).first
        )
        let chart = try #require(section.tokens.first?.chart)

        guard case .sparkline(let points, let tint) = chart else {
            Issue.record("Expected a dynamic sparkline")
            return
        }
        #expect(points == [1, 0, 0.5])
        #expect(tint == 0x123456)
    }

    @Test
    func `keeps the localized backend name when a stored token is available`() throws {
        let response = try makeResponse(
            title: "Popular Tokens",
            limit: nil,
            hasMore: false,
            assetCount: 1,
            assetName: "Локализованное имя"
        )
        let storedToken = ApiToken(
            slug: "asset-0",
            name: "Original Name",
            symbol: "A0",
            decimals: 9,
            chain: .ton
        )
        let section = try #require(
            MarketSectionBuilder.build(
                from: response,
                storeTokens: [storedToken.slug: storedToken]
            ).first
        )

        #expect(section.tokens.first?.token.name == "Original Name")
        #expect(section.tokens.first?.token.localizedName == "Локализованное имя")
    }

    private func makeResponse(
        title: String,
        limit: Int?,
        mobileLimit: Int? = nil,
        desktopLimit: Int? = nil,
        hasMore: Bool,
        assetCount: Int,
        sparkline: [Double]? = nil,
        tintColor: String? = nil,
        assetName: String = "Asset",
        layout: String = "grid"
    ) throws -> ApiMarketAssetsResponse {
        let assets: [[String: Any]] = (0..<assetCount).map { index in
            var asset: [String: Any] = [
                "newBackendId": "ton:asset-\(index)",
                "slug": "asset-\(index)",
                "name": assetName,
                "symbol": "A\(index)",
                "chain": "ton",
                "image": "",
                "price": 2.5,
                "percentChange24h": 1.25,
            ]
            asset["sparkline"] = sparkline
            asset["tintColor"] = tintColor
            return asset
        }
        var section: [String: Any] = [
            "id": "section",
            "title": title,
            "layout": layout,
            "hasMore": hasMore,
            "assets": assets,
        ]
        section["limit"] = limit
        section["mobileLimit"] = mobileLimit
        section["desktopLimit"] = desktopLimit
        let data = try JSONSerialization.data(withJSONObject: ["sections": [section]])
        return try JSONDecoder().decode(ApiMarketAssetsResponse.self, from: data)
    }
}
