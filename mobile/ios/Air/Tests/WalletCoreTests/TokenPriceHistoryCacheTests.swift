import Foundation
import Testing
import WalletContext
@testable import WalletCore

@MainActor
@Suite("Token Price History Cache", .serialized)
struct TokenPriceHistoryCacheTests {
    @Test
    func `empty responses are not restored as cached history`() {
        let slug = "test-empty-price-history-\(UUID())"
        let currency = TokenStore.baseCurrency
        let emptyHistory = ApiPriceHistory(points: [], backfill: nil)
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: emptyHistory, baseCurrency: currency))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == nil)

        let history = ApiPriceHistory(points: [[Date.now.timeIntervalSince1970, 10.0]], backfill: nil)
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: history, baseCurrency: currency))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == history)
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: emptyHistory, baseCurrency: currency))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == nil)
    }

    @Test
    func `cached stock history survives serialization`() throws {
        let slug = "test-stock-price-history-\(UUID())"
        let now = Date.now.timeIntervalSince1970
        let history = ApiPriceHistory(
            points: [[now, 400]],
            backfill: ApiPriceHistoryBackfill(symbol: "TSLA", points: [[now - 60, 399]])
        )
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .all, history: history, baseCurrency: TokenStore.baseCurrency))
        let cached = try #require(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .all))
        #expect(cached == history)
        let data = try JSONEncoder().encode([slug: [ApiPriceHistoryPeriod.all.rawValue: cached]])
        let restored = try JSONDecoder().decode([String: [String: ApiPriceHistory]].self, from: data)
        #expect(restored[slug]?[ApiPriceHistoryPeriod.all.rawValue] == history)
    }

    @Test
    func `legacy point-only caches cannot be restored as complete history`() throws {
        let cache = ["stock": [ApiPriceHistoryPeriod.all.rawValue: [[Date.now.timeIntervalSince1970, 400.0]]]]
        let data = try JSONEncoder().encode(cache)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([String: [String: ApiPriceHistory]].self, from: data)
        }
    }

    @Test
    func `stock-only history is not restored without token history`() {
        let slug = "test-stock-history-expiry-\(UUID())"
        let history = ApiPriceHistory(
            points: [],
            backfill: ApiPriceHistoryBackfill(symbol: "TSLA", points: [[Date.now.timeIntervalSince1970, 400]])
        )
        let currency = TokenStore.baseCurrency
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: history, baseCurrency: currency))
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .all, history: history, baseCurrency: currency))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == nil)
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .all) == nil)
    }

    @Test
    func `currency changes remove the persisted history and reject late responses`() async throws {
        let originalCurrency = TokenStore.baseCurrency
        let currency: MBaseCurrency = originalCurrency == .USD ? .EUR : .USD
        let slug = "test-price-history-currency"
        let history = ApiPriceHistory(points: [[Date.now.timeIntervalSince1970, 10.0]], backfill: nil)
        let cacheURL = URL.cachesDirectory.appending(components: "air", "price-history-cache.json")

        // Represents a chart persisted before this app session.
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let cache = [slug: [ApiPriceHistoryPeriod.day.rawValue: history]]
        try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path()))

        try await TokenStore.setBaseCurrency(currency: currency)
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path()))
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: history, baseCurrency: originalCurrency) == false)
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == nil)

        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: history, baseCurrency: currency))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == history)

        try await TokenStore.setBaseCurrency(currency: originalCurrency)
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path()))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == nil)
    }
}
