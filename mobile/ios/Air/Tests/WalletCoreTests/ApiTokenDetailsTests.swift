import Foundation
import Testing
@testable import WalletCore

@Suite("Api Token Details")
struct ApiTokenDetailsTests {
    @Test
    func `decodes raw SDK token info payload and matches the slug`() throws {
        let data = Data(
            #"""
            [
              {
                "slug": "other-token",
                "tokenInfo": { "description": "Wrong token" }
              },
              {
                "slug": "gram",
                "tokenInfo": {
                  "description": "Original description",
                  "localizedDescription": "Localized description",
                  "marketCap": 7580000000,
                  "supply": {
                    "circulating": 5120000000,
                    "total": 6000000000
                  },
                  "createdAt": "2019-11-15T00:00:00.000Z",
                  "volume24h": {
                    "sell": 1580000,
                    "buy": 2440000,
                    "percentChange": 89.46
                  },
                  "links": [
                    { "url": "https://x.com/gram", "type": "x" },
                    { "url": "https://t.me/gram", "type": "telegram" },
                    { "url": "https://gramcoin.org" }
                  ],
                  "aggregatorLinks": [
                    { "url": "https://example.com/gram", "name": "Aggregator" }
                  ],
                  "docsUrl": "https://gramcoin.org/docs",
                  "sourceCodeUrl": "https://github.com/gramcoin"
                }
              }
            ]
            """#.utf8
        )

        let response = try JSONDecoder().decode([ApiTokenDetailsResponse].self, from: data)
        let details = try #require(response.first { $0.slug == "gram" }?.tokenInfo)

        #expect(details.description == "Original description")
        #expect(details.localizedDescription == "Localized description")
        #expect(details.marketCap == 7_580_000_000)
        #expect(details.circulatingSupply == 5_120_000_000)
        #expect(details.totalSupply == 6_000_000_000)
        #expect(details.createdAt != nil)
        #expect(details.volume24h?.total == 4_020_000)
        #expect(details.volume24h?.change == 0.8946)
        #expect(details.links?.map(\.kind) == [
            .x,
            .telegram,
            .website,
            .aggregator,
            .documentation,
            .sourceCode,
        ])
    }

    @Test
    func `decodes volume without percent change`() throws {
        let data = Data(
            #"""
            [
              {
                "slug": "gram",
                "tokenInfo": {
                  "volume24h": {
                    "sell": 1580000,
                    "buy": 2440000
                  }
                }
              }
            ]
            """#.utf8
        )

        let response = try JSONDecoder().decode([ApiTokenDetailsResponse].self, from: data)
        let details = try #require(response.first?.tokenInfo)
        let volume = try #require(details.volume24h)

        #expect(volume.total == 4_020_000)
        #expect(volume.buy == 2_440_000)
        #expect(volume.sell == 1_580_000)
        #expect(volume.change == nil)
    }

    @Test
    func `preserves token info when nested metrics are incomplete`() throws {
        let data = Data(
            #"""
            [
              {
                "slug": "gram",
                "tokenInfo": {
                  "description": "Description survives partial metrics",
                  "supply": {
                    "circulating": 5120000000
                  },
                  "volume24h": {
                    "buy": 2440000
                  }
                }
              }
            ]
            """#.utf8
        )

        let response = try JSONDecoder().decode([ApiTokenDetailsResponse].self, from: data)
        let details = try #require(response.first?.tokenInfo)

        #expect(details.description == "Description survives partial metrics")
        #expect(details.circulatingSupply == 5_120_000_000)
        #expect(details.totalSupply == nil)
        #expect(details.volume24h == nil)
    }

    @Test
    func `preserves valid token info when optional fields and link entries are malformed`() throws {
        let data = Data(
            #"""
            [
              {
                "slug": "gram",
                "tokenInfo": {
                  "description": "Description survives malformed optional data",
                  "localizedDescription": 42,
                  "marketCap": "unknown",
                  "supply": {
                    "circulating": "unknown",
                    "total": 6000000000
                  },
                  "createdAt": false,
                  "volume24h": {
                    "sell": 1580000,
                    "buy": 2440000,
                    "percentChange": "unknown"
                  },
                  "links": [
                    { "url": "https://x.com/gram", "type": "x" },
                    { "type": "telegram" },
                    "invalid"
                  ],
                  "aggregatorLinks": [
                    { "url": "https://example.com/gram", "name": "Aggregator" },
                    { "url": "https://example.com/broken" }
                  ],
                  "docsUrl": 42,
                  "sourceCodeUrl": "https://github.com/gramcoin"
                }
              }
            ]
            """#.utf8
        )

        let response = try JSONDecoder().decode([ApiTokenDetailsResponse].self, from: data)
        let details = try #require(response.first?.tokenInfo)

        #expect(details.description == "Description survives malformed optional data")
        #expect(details.localizedDescription == nil)
        #expect(details.marketCap == nil)
        #expect(details.circulatingSupply == nil)
        #expect(details.totalSupply == 6_000_000_000)
        #expect(details.createdAt == nil)
        #expect(details.volume24h?.total == 4_020_000)
        #expect(details.volume24h?.change == nil)
        #expect(details.links?.map(\.kind) == [.x, .aggregator, .sourceCode])
    }

    @Test
    func `caches missing token info separately from a cache miss`() throws {
        let slug = "missing-token-info-\(UUID().uuidString)"

        #expect(TokenStore.cachedTokenDetails(tokenSlug: slug) == nil)
        TokenStore.setCachedTokenDetails(tokenSlug: slug, details: nil)

        let cached = try #require(TokenStore.cachedTokenDetails(tokenSlug: slug))
        #expect(cached.details == nil)
    }
}
