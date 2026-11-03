import Testing
@testable import WalletCore

@Suite("Token Details Batch", .timeLimit(.minutes(1)))
struct TokenDetailsBatchTests {
    @Test
    func `twenty uncached tokens share one fetch and missing details remain nil`() async throws {
        let tokens = [ApiToken.TONCOIN] + (1..<20).map(makeToken)
        let fetcher = TokenDetailsBatchFetcher()
        var inFlight: [String: TokenDetailsRequest] = [:]
        let requests = _TokenStore.startTokenDetailsRequests(
            language: "en", tokens: tokens, requests: &inFlight,
            fetch: { try await fetcher.fetch($0) }
        )
        var calls = fetcher.calls.makeAsyncIterator()
        let call = await calls.next()
        #expect(call?.map(\.asset) == tokens.map(\.swapIdentifier))
        #expect(call?.map(\.slug) == tokens.map(\.slug))
        #expect(inFlight.count == 20)

        let details = Dictionary(uniqueKeysWithValues: tokens.dropLast().map { ($0.slug, makeDetails($0.slug)) })
        await fetcher.finish(.success(details))
        for token in tokens {
            let request = try #require(requests[token.slug])
            #expect(try await request.task.value == details[token.slug])
        }
        #expect(await fetcher.callCount == 1)
    }

    @Test
    func `duplicate slugs fetch the first asset once`() async throws {
        let token = makeToken(0)
        var duplicate = token
        duplicate.tokenAddress = "EQ_DUPLICATE"
        let fetcher = TokenDetailsBatchFetcher()
        var inFlight: [String: TokenDetailsRequest] = [:]
        let requests = _TokenStore.startTokenDetailsRequests(
            language: "en", tokens: [token, duplicate], requests: &inFlight,
            fetch: { try await fetcher.fetch($0) }
        )
        var calls = fetcher.calls.makeAsyncIterator()
        let call = await calls.next()
        #expect(call?.map(\.asset) == [token.swapIdentifier])
        #expect(call?.map(\.slug) == [token.slug])
        #expect(inFlight.count == 1)
        #expect(requests.count == 1)

        let details = makeDetails(token.slug)
        await fetcher.finish(.success([token.slug: details]))
        let request = try #require(requests[token.slug])
        #expect(try await request.task.value == details)
        #expect(await fetcher.callCount == 1)
    }

    @Test
    func `no uncached tokens issue no fetch`() {
        var inFlight: [String: TokenDetailsRequest] = [:]
        let requests = _TokenStore.startTokenDetailsRequests(
            language: "en", tokens: [], requests: &inFlight,
            fetch: { _ in
                Issue.record("An empty token list must not fetch token details")
                return [:]
            }
        )
        #expect(requests.isEmpty)
        #expect(inFlight.isEmpty)
    }

    @Test
    func `a token screen joins a suspended preload and receives its own details`() async throws {
        let tokens = (0..<2).map(makeToken)
        let fetcher = TokenDetailsBatchFetcher()
        var inFlight: [String: TokenDetailsRequest] = [:]
        let preload = _TokenStore.startTokenDetailsRequests(
            language: "en", tokens: tokens, requests: &inFlight,
            fetch: { try await fetcher.fetch($0) }
        )
        var calls = fetcher.calls.makeAsyncIterator()
        let call = await calls.next()
        #expect(call != nil)

        let screen = _TokenStore.startTokenDetailsRequests(
            language: "en", tokens: [tokens[1]], requests: &inFlight,
            fetch: { try await fetcher.fetch($0) }
        )
        #expect(screen[tokens[1].slug]?.id == preload[tokens[1].slug]?.id)

        let details = Dictionary(uniqueKeysWithValues: tokens.map { ($0.slug, makeDetails($0.slug)) })
        await fetcher.finish(.success(details))
        let screenRequest = try #require(screen[tokens[1].slug])
        #expect(try await screenRequest.task.value == details[tokens[1].slug])
        for (slug, request) in preload {
            #expect(try await request.task.value == details[slug])
        }
        #expect(await fetcher.callCount == 1)
    }

    @Test
    func `a partially in-flight batch fetches only the remaining tokens`() async throws {
        let tokens = (0..<3).map(makeToken)
        let fetcher = TokenDetailsBatchFetcher()
        var inFlight: [String: TokenDetailsRequest] = [:]
        let existing = _TokenStore.startTokenDetailsRequests(
            language: "en", tokens: [tokens[0]], requests: &inFlight,
            fetch: { try await fetcher.fetch($0) }
        )
        var calls = fetcher.calls.makeAsyncIterator()
        let firstCall = await calls.next()
        #expect(firstCall?.map(\.asset) == [tokens[0].swapIdentifier])

        let batch = _TokenStore.startTokenDetailsRequests(
            language: "en", tokens: tokens, requests: &inFlight,
            fetch: { try await fetcher.fetch($0) }
        )
        let secondCall = await calls.next()
        #expect(secondCall?.map(\.asset) == tokens.dropFirst().map(\.swapIdentifier))
        #expect(batch[tokens[0].slug]?.id == existing[tokens[0].slug]?.id)

        let details = Dictionary(uniqueKeysWithValues: tokens.map { ($0.slug, makeDetails($0.slug)) })
        await fetcher.finish(.success(details))
        for (slug, request) in batch {
            #expect(try await request.task.value == details[slug])
        }
        #expect(await fetcher.callCount == 2)
    }

    @Test
    func `a failed batch propagates the error to every token`() async {
        let fetcher = TokenDetailsBatchFetcher()
        var inFlight: [String: TokenDetailsRequest] = [:]
        let requests = _TokenStore.startTokenDetailsRequests(
            language: "en", tokens: (0..<3).map(makeToken), requests: &inFlight,
            fetch: { try await fetcher.fetch($0) }
        )
        await fetcher.finish(.failure(.expected))
        for request in requests.values {
            await #expect(throws: TokenDetailsBatchError.self) {
                try await request.task.value
            }
        }
        #expect(await fetcher.callCount == 1)
    }

    private func makeToken(_ index: Int) -> ApiToken {
        ApiToken(
            slug: "ton-batch-\(index)", name: "Batch Token \(index)", symbol: "BATCH",
            decimals: 9, chain: .ton, tokenAddress: "EQ_BATCH_\(index)"
        )
    }

    private func makeDetails(_ slug: String) -> ApiTokenDetails {
        ApiTokenDetails(
            description: slug, links: nil, marketCap: nil, circulatingSupply: nil,
            totalSupply: nil, createdAt: nil, volume24h: nil
        )
    }
}

private enum TokenDetailsBatchError: Error {
    case expected
}

private actor TokenDetailsBatchFetcher {
    nonisolated let calls: AsyncStream<[(asset: String, slug: String)]>
    private let callContinuation: AsyncStream<[(asset: String, slug: String)]>.Continuation
    private var pending: [CheckedContinuation<[String: ApiTokenDetails], Error>] = []
    private var result: Result<[String: ApiTokenDetails], TokenDetailsBatchError>?
    private(set) var callCount = 0

    init() {
        let stream = AsyncStream.makeStream(of: [(asset: String, slug: String)].self)
        calls = stream.stream
        callContinuation = stream.continuation
    }

    func fetch(_ tokens: [(asset: String, slug: String)]) async throws -> [String: ApiTokenDetails] {
        callCount += 1
        callContinuation.yield(tokens)
        if let result {
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }

    func finish(_ result: Result<[String: ApiTokenDetails], TokenDetailsBatchError>) {
        self.result = result
        for continuation in pending {
            continuation.resume(with: result.mapError { $0 as Error })
        }
        pending.removeAll()
        callContinuation.finish()
    }
}
