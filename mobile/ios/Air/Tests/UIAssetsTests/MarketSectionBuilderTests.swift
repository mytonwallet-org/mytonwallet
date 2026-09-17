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
        #expect(section.visibleTokens.count == 2)
        #expect(section.showsSeeAll)
    }

    @Test
    func `prefers mobileLimit over desktopLimit for the showcase`() throws {
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

        #expect(section.tokens.count == 12)
        #expect(section.visibleTokens.count == 8)
        #expect(section.showsSeeAll)
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
        assetName: String = "Asset"
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
            "layout": "grid",
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
