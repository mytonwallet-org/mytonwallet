import Foundation
import Testing
@testable import WalletCore

@Suite
struct MarketAssetsCacheTests {
    @Test func restoresSavedSectionsAfterRecreatingTheCache() async throws {
        let directory = URL.temporaryDirectory.appending(component: "Market cache \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheUrl = directory.appending(component: "market.json")
        let response = try JSONDecoder().decode(ApiMarketAssetsResponse.self, from: Data(#"""
        {"sections":[{"id":"popular","title":"Popular Tokens","layout":"grid","hasMore":false,"assets":[
        {"newBackendId":"ton:native","slug":"toncoin","name":"Toncoin","symbol":"TON","chain":"ton","image":"","price":1,"percentChange24h":0}
        ]}]}
        """#.utf8))
        await MarketAssetsCache(cacheURL: cacheUrl).save(response, langCode: "en")

        let restored = MarketAssetsCache(cacheURL: cacheUrl)
        #expect(await restored.load(langCode: "en") == response)
        #expect(await restored.load(langCode: "ru") == nil)
        #expect(await restored.load(langCode: "en") == response)
    }
}
