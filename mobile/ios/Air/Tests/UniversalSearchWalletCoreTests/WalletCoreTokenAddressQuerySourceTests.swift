import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletCoreTypes

@MainActor
@Suite("WalletCore token address query source")
struct WalletCoreTokenAddressQuerySourceTests {
    private let accountID = "account-mainnet"
    private let context = UniversalSearchContext(
        scopeID: "account-mainnet",
        network: "mainnet",
        localeIdentifier: "en"
    )
    private let address = ApiToken.TON_USDT.tokenAddress!

    @Test
    func `recognizes only supported chains that can discover tokens`() {
        let allSupported: [ApiChain] = [.ton, .tron, .solana, .ethereum]

        #expect(WalletCoreTokenAddressQuerySource.candidateChains(
            for: address,
            supportedChains: allSupported
        ) == [.ton])
        #expect(WalletCoreTokenAddressQuerySource.candidateChains(
            for: ApiToken.TRON_USDT.tokenAddress!,
            supportedChains: allSupported
        ).isEmpty)
        #expect(WalletCoreTokenAddressQuerySource.candidateChains(
            for: "not-an-address",
            supportedChains: allSupported
        ).isEmpty)
    }

    @Test
    func `does not fetch an address already owned by the local corpus`() async throws {
        let recorder = TokenFetchRecorder(result: .success(ApiToken.TON_USDT))
        let source = makeSource(
            recorder: recorder,
            knownTokens: [.TON_USDT]
        )

        let snapshots = try await collect(source.snapshots(
            for: UniversalSearchQuery(address),
            context: context
        ))

        #expect(snapshots.isEmpty)
        #expect(await recorder.callCount == 0)
    }

    @Test
    func `discovers caches and reuses a token across repeated queries`() async throws {
        let discovered = ApiToken(
            slug: "ton-discovered",
            name: "Discovered Token",
            symbol: "DISC",
            decimals: 9,
            chain: .ton,
            tokenAddress: address
        )
        let recorder = TokenFetchRecorder(result: .success(discovered))
        let registry = WalletCoreSearchEntityRegistry()
        let source = makeSource(registry: registry, recorder: recorder)

        let first = try await collect(source.snapshots(
            for: UniversalSearchQuery(address),
            context: context
        ))
        let second = try await collect(source.snapshots(
            for: UniversalSearchQuery(address),
            context: context
        ))
        let firstDocument = try #require(first.first?.documents.first)

        #expect(first.count == 1)
        #expect(second.count == 1)
        #expect(await recorder.callCount == 1)
        #expect(firstDocument.id == SearchEntityID("token:ton-discovered"))
        #expect(firstDocument.fields.first { $0.kind == .address }?.value == address)
        #expect(registry.token(accountID: accountID, slug: discovered.slug) == discovered)
    }

    @Test
    func `a failed lookup finishes without contributing documents`() async throws {
        let recorder = TokenFetchRecorder(result: .failure(TestError.unavailable))
        let source = makeSource(recorder: recorder)

        let snapshots = try await collect(source.snapshots(
            for: UniversalSearchQuery(address),
            context: context
        ))

        #expect(snapshots.isEmpty)
        #expect(await recorder.callCount == 1)
    }

    @Test
    func `cancelling the query cancels its in flight lookup`() async throws {
        let recorder = TokenFetchRecorder(result: .suspended)
        let source = makeSource(recorder: recorder)
        let consumer = Task {
            try await collect(source.snapshots(
                for: UniversalSearchQuery(address),
                context: context
            ))
        }

        defer { consumer.cancel() }
        let lookupDeadline = ContinuousClock.now + .seconds(1)
        while await recorder.callCount == 0, ContinuousClock.now < lookupDeadline {
            await Task.yield()
        }
        try #require(await recorder.callCount == 1)
        consumer.cancel()
        _ = try? await consumer.value
        let cancellationDeadline = ContinuousClock.now + .seconds(1)
        while await recorder.cancellationCount == 0, ContinuousClock.now < cancellationDeadline {
            await Task.yield()
        }

        #expect(await recorder.cancellationCount == 1)
    }

    private func makeSource(
        registry: WalletCoreSearchEntityRegistry = .init(),
        recorder: TokenFetchRecorder,
        knownTokens: [ApiToken] = []
    ) -> WalletCoreTokenAddressQuerySource {
        WalletCoreTokenAddressQuerySource(
            registry: registry,
            inputLoader: { _ in
                WalletCoreTokenAddressSearchInput(
                    accountID: accountID,
                    supportedChains: [.ton, .tron, .solana, .ethereum],
                    knownTokens: knownTokens
                )
            },
            fetcher: { accountID, chain, address in
                try await recorder.fetch(
                    accountID: accountID,
                    chain: chain,
                    address: address
                )
            },
            clock: { Date(timeIntervalSince1970: 42) }
        )
    }
}

private actor TokenFetchRecorder {
    enum Result: Sendable {
        case success(ApiToken)
        case failure(any Error & Sendable)
        case suspended
    }

    private let result: Result
    private(set) var callCount = 0
    private(set) var cancellationCount = 0

    init(result: Result) {
        self.result = result
    }

    func fetch(
        accountID: String,
        chain: ApiChain,
        address: String
    ) async throws -> ApiToken {
        callCount += 1
        switch result {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        case .suspended:
            do {
                try await Task.sleep(for: .seconds(30))
                throw TestError.unavailable
            } catch is CancellationError {
                cancellationCount += 1
                throw CancellationError()
            }
        }
    }
}

private enum TestError: Error, Sendable {
    case unavailable
}

private func collect(
    _ stream: AsyncThrowingStream<UniversalSearchSourceSnapshot, Error>
) async throws -> [UniversalSearchSourceSnapshot] {
    var snapshots: [UniversalSearchSourceSnapshot] = []
    for try await snapshot in stream {
        snapshots.append(snapshot)
    }
    return snapshots
}
