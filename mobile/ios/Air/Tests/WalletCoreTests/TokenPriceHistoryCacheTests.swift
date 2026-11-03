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
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: [], baseCurrency: currency))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == nil)

        let history = [[Date.now.timeIntervalSince1970, 10.0]]
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: history, baseCurrency: currency))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == history)
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .day, history: [], baseCurrency: currency))
        #expect(TokenStore.cachedPriceHistory(tokenSlug: slug, period: .day) == nil)
    }

    @Test
    func `currency changes remove the persisted history and reject late responses`() async throws {
        let originalCurrency = TokenStore.baseCurrency
        let currency: MBaseCurrency = originalCurrency == .USD ? .EUR : .USD
        let slug = "test-price-history-currency"
        let history = [[Date.now.timeIntervalSince1970, 10.0]]
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
