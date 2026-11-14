import Foundation
import GRDB
import Testing
import WalletContext
@testable import WalletCore
@testable import UIToken

@MainActor
@Suite("Token Price History State", .serialized, .settingsStoreIsolation, .timeLimit(.minutes(1)))
struct TokenPriceHistoryStateTests {
    @Test
    func `a search token loads with its identity and recovers from failure on retry`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var requests = fixture.requests.makeAsyncIterator()
        var updates = fixture.delegate.updates.makeAsyncIterator()
        fixture.model.loadPriceHistory(period: .day)
        #expect(await updates.next() == .loading)
        let first = try #require(await requests.next())
        #expect(first.token == fixture.token)
        #expect(first.period == .day)
        #expect(first.currency == TokenStore.baseCurrency)
        first.continuation.resume(throwing: Failure.offline)
        #expect(await updates.next() == .failed)
        #expect(fixture.model.historyData == nil)
        #expect(TokenStore.cachedPriceHistory(tokenSlug: fixture.token.slug, period: .day) == nil)

        fixture.model.loadPriceHistory(period: .day)
        #expect(await updates.next() == .loading)
        let retry = try #require(await requests.next())
        retry.continuation.resume(returning: fixture.history)
        #expect(await updates.next() == .loaded)
        #expect(fixture.model.historyData == fixture.history)
        #expect(!fixture.model.isHistoryRestored)
    }

    @Test
    func `a failed request retries automatically without reopening the screen`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var requests = fixture.requests.makeAsyncIterator()
        var updates = fixture.delegate.updates.makeAsyncIterator()
        fixture.model.loadPriceHistory(period: .day)
        #expect(await updates.next() == .loading)
        let first = try #require(await requests.next())
        first.continuation.resume(throwing: Failure.offline)
        #expect(await updates.next() == .failed)

        #expect(await updates.next() == .loading)
        let retry = try #require(await requests.next())
        retry.continuation.resume(returning: fixture.history)
        #expect(await updates.next() == .loaded)
        #expect(fixture.model.historyData == fixture.history)
    }

    @Test
    func `a cached chart survives a failed refresh`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        #expect(TokenStore.setPriceHistory(tokenSlug: fixture.token.slug, period: .day,
            history: ApiPriceHistory(points: fixture.history, backfill: nil), baseCurrency: TokenStore.baseCurrency))
        var requests = fixture.requests.makeAsyncIterator()
        var updates = fixture.delegate.updates.makeAsyncIterator()
        fixture.model.loadPriceHistory(period: .day)
        #expect(await updates.next() == .loading)
        #expect(fixture.model.historyData == fixture.history)
        let request = try #require(await requests.next())
        request.continuation.resume(throwing: Failure.offline)
        #expect(await updates.next() == .failed)
        #expect(fixture.model.historyData == fixture.history)
        #expect(fixture.model.isHistoryRestored)
    }

    @Test(arguments: [false, true])
    func `reopening restores only stock charts with token history`(hasTokenHistory: Bool) async throws {
        let backfill = ApiPriceHistoryBackfill(symbol: "TSLA", points: [[Date.now.timeIntervalSince1970 - 120, 300]])
        let fixture = try Fixture(backfill: backfill)
        defer { fixture.close() }
        let history = hasTokenHistory ? fixture.history : []
        var requests = fixture.requests.makeAsyncIterator()
        var updates = fixture.delegate.updates.makeAsyncIterator()
        fixture.model.selectedPeriod = .all
        #expect(await updates.next() == .loading)
        let first = try #require(await requests.next())
        first.continuation.resume(returning: history)
        #expect(await updates.next() == .loaded)

        let reopenedDelegate = Delegate()
        let reopened = TokenVM(accountId: "test-mainnet", selectedToken: fixture.token, tokenVMDelegate: reopenedDelegate)
        reopened.reachability.whenReachable = nil
        reopened.reachability.whenUnreachable = nil
        reopened.reachability.stopNotifier()
        defer { reopened.stopAllObservers() }
        #expect(reopened.selectedPeriod == .all)
        #expect(reopened.historyData == (hasTokenHistory ? history : nil))
        #expect(reopened.backfill == (hasTokenHistory ? backfill : nil))
        #expect(reopened.isHistoryRestored)

        fixture.model.loadPriceHistory(period: .all)
        #expect(await updates.next() == .loading)
        let refresh = try #require(await requests.next())
        #expect(fixture.model.historyData == (hasTokenHistory ? history : nil))
        #expect(fixture.model.backfill == (hasTokenHistory ? backfill : nil))
        refresh.continuation.resume(throwing: Failure.offline)
        #expect(await updates.next() == .failed)
        #expect(fixture.model.historyData == (hasTokenHistory ? history : nil))
        #expect(fixture.model.backfill == (hasTokenHistory ? backfill : nil))
    }

    @Test
    func `an empty result finishes loading but reopening starts a new load`() async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var requests = fixture.requests.makeAsyncIterator()
        var updates = fixture.delegate.updates.makeAsyncIterator()
        fixture.model.loadPriceHistory(period: .day)
        #expect(await updates.next() == .loading)
        let request = try #require(await requests.next())
        request.continuation.resume(returning: [])
        #expect(await updates.next() == .loaded)
        #expect(fixture.model.historyData == [])

        fixture.model.loadPriceHistory(period: .day)
        #expect(await updates.next() == .loading)
        #expect(fixture.model.historyData == nil)
        let retry = try #require(await requests.next())
        retry.continuation.resume(returning: fixture.history)
        #expect(await updates.next() == .loaded)
    }

    @Test(arguments: [false, true])
    func `a cancelled period response cannot replace the new period state`(fails: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        var requests = fixture.requests.makeAsyncIterator()
        var updates = fixture.delegate.updates.makeAsyncIterator()
        fixture.model.loadPriceHistory(period: .day)
        #expect(await updates.next() == .loading)
        let old = try #require(await requests.next())
        fixture.model.selectedPeriod = .week
        #expect(await updates.next() == .loading)
        let current = try #require(await requests.next())
        current.continuation.resume(returning: fixture.history)
        #expect(await updates.next() == .loaded)

        if fails {
            old.continuation.resume(throwing: Failure.offline)
        } else {
            old.continuation.resume(returning: [])
        }
        // Let the resumed request reach the cancellation guard before checking the state.
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.model.historyLoadingState == .loaded)
        #expect(fixture.model.historyData == fixture.history)
        #expect(TokenStore.cachedPriceHistory(tokenSlug: fixture.token.slug, period: .day) == nil)
    }

    private enum Failure: Error { case offline }

    private struct Request {
        let token: ApiToken
        let period: ApiPriceHistoryPeriod
        let currency: MBaseCurrency
        let continuation: CheckedContinuation<ApiHistoryList, Error>
    }

    @MainActor private final class Fixture {
        let token = ApiToken(slug: "test-chart-\(UUID())", name: "Tesla", symbol: "TSLAx", decimals: 8,
                             chain: .ton, tokenAddress: "EQ_TEST")
        let history = [[Date.now.timeIntervalSince1970 - 60, 399.0], [Date.now.timeIntervalSince1970, 400.0]]
        let delegate = Delegate()
        let requests: AsyncStream<Request>
        let model: TokenVM

        init(backfill: ApiPriceHistoryBackfill? = nil) throws {
            let db = try DatabaseQueue()
            try makeMigrator().migrate(db)
            SettingsStore.liveValue.use(db: db)
            let (requests, continuation) = AsyncStream<Request>.makeStream()
            self.requests = requests
            model = TokenVM(accountId: "test-mainnet", selectedToken: token, tokenVMDelegate: delegate) { token, period, currency in
                let points = try await withCheckedThrowingContinuation { response in
                    continuation.yield(Request(token: token, period: period, currency: currency, continuation: response))
                }
                return ApiPriceHistory(points: points, backfill: backfill)
            }
            model.reachability.whenReachable = nil
            model.reachability.whenUnreachable = nil
            model.reachability.stopNotifier()
            delegate.model = model
        }

        func close() {
            model.stopAllObservers()
            SettingsStore.liveValue.clean()
        }
    }

    private final class Delegate: TokenVMDelegate {
        weak var model: TokenVM?
        let updates: AsyncStream<TokenHistoryLoadingState>
        let continuation: AsyncStream<TokenHistoryLoadingState>.Continuation

        init() { (updates, continuation) = AsyncStream.makeStream() }
        func priceDataUpdated() { if let model { continuation.yield(model.historyLoadingState) } }
        func dataUpdated() {}
        func tokenDetailsUpdated() {}
        func accountChanged() {}
    }
}
