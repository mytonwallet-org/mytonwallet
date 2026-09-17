import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletCoreTypes

@MainActor
@Suite("WalletCore wallet address query source")
struct WalletCoreWalletAddressQuerySourceTests {
    private let context = UniversalSearchContext(
        scopeID: "account-mainnet",
        network: "mainnet",
        localeIdentifier: "en"
    )
    private let address = ApiToken.TON_USDT.tokenAddress!

    @Test
    func `recognizes supported wallet addresses and chain DNS names`() {
        let chains: [ApiChain] = [.ton, .tron, .solana, .ethereum]

        #expect(WalletCoreWalletAddressQuerySource.candidateChains(
            for: address,
            chains: chains
        ) == [.ton])
        #expect(WalletCoreWalletAddressQuerySource.candidateChains(
            for: "mwme.ton",
            chains: chains
        ) == [.ton])
        #expect(WalletCoreWalletAddressQuerySource.candidateChains(
            for: "fragment.com",
            chains: chains
        ).isEmpty)
    }

    @Test
    func `valid address appears immediately and is then enriched`() async throws {
        let recorder = WalletResolutionRecorder(result: .success(.init(
            addressName: "Tether Treasury",
            resolvedAddress: address
        )))
        let source = makeSource(recorder: recorder)

        let snapshots = try await collectWalletSnapshots(source.snapshots(
            for: UniversalSearchQuery(address),
            context: context
        ))

        #expect(snapshots.count == 2)
        let initialDocument = try #require(snapshots[0].documents.first)
        let resolvedDocument = try #require(snapshots[1].documents.first)
        #expect(initialDocument.attributeValue(
            for: WalletCoreSearchAttributeKey.addressName
        ) == nil)
        #expect(resolvedDocument.attributeValue(
            for: WalletCoreSearchAttributeKey.addressName
        ) == "Tether Treasury")
        #expect(resolvedDocument.signals.traits.contains(.external))
        #expect(await recorder.callCount == 1)
    }

    @Test
    func `DNS placeholder is replaced by the resolved wallet`() async throws {
        let resolvedAddress = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
        let recorder = WalletResolutionRecorder(result: .success(.init(
            addressName: "My Wallet",
            resolvedAddress: resolvedAddress
        )))
        let source = makeSource(recorder: recorder)

        let snapshots = try await collectWalletSnapshots(source.snapshots(
            for: UniversalSearchQuery("mwme.ton"),
            context: context
        ))
        let placeholder = try #require(snapshots.first?.documents.first)
        let document = try #require(snapshots.last?.documents.first)

        #expect(snapshots.count == 2)
        #expect(placeholder.id == document.id)
        #expect(placeholder.attributeValue(for: WalletCoreSearchAttributeKey.isResolvingDomain) == "true")
        #expect(placeholder.attributeValue(for: WalletCoreSearchAttributeKey.address) == nil)
        #expect(document.attributeValue(for: WalletCoreSearchAttributeKey.isResolvingDomain) == nil)
        #expect(document.fields.first { $0.kind == .domain }?.value == "mwme.ton")
        #expect(document.attributeValue(for: WalletCoreSearchAttributeKey.address) == resolvedAddress)
        #expect(document.attributeValue(
            for: WalletCoreSearchAttributeKey.inputAddressOrDomain
        ) == "mwme.ton")
    }

    @Test(arguments: [false, true])
    func `failed DNS resolution removes the placeholder`(throwsError: Bool) async throws {
        let recorder = WalletResolutionRecorder(result: throwsError
            ? .failure(WalletResolutionTestError.failed)
            : .success(.init(error: "UnresolvedDomain")))
        let source = makeSource(recorder: recorder)

        let snapshots = try await collectWalletSnapshots(source.snapshots(
            for: UniversalSearchQuery("mwme.ton"),
            context: context
        ))

        #expect(snapshots.count == 2)
        #expect(snapshots.first?.documents.first?.attributeValue(
            for: WalletCoreSearchAttributeKey.isResolvingDomain
        ) == "true")
        #expect(snapshots.last?.documents.isEmpty == true)
    }

    @Test(arguments: ["mwme.ton", "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"])
    func `known wallet identifier is left to the local wallet source`(identifier: String) async throws {
        let recorder = WalletResolutionRecorder(result: .success(.init(
            resolvedAddress: address
        )))
        let source = makeSource(
            recorder: recorder,
            knownWalletIdentifiers: [identifier.lowercased()]
        )

        let snapshots = try await collectWalletSnapshots(source.snapshots(
            for: UniversalSearchQuery(identifier),
            context: context
        ))

        #expect(snapshots.isEmpty)
        #expect(await recorder.callCount == 0)
    }

    @Test
    func `address valid on multiple supported chains produces a result for each chain`() async throws {
        let evmAddress = "0x\(String(repeating: "a", count: 40))"
        let recorder = WalletResolutionRecorder(result: .success(.init(
            resolvedAddress: evmAddress
        )))
        let source = makeSource(
            recorder: recorder,
            supportedChains: [.ethereum, .base]
        )

        let snapshots = try await collectWalletSnapshots(source.snapshots(
            for: UniversalSearchQuery(evmAddress),
            context: context
        ))
        let finalDocuments = try #require(snapshots.last?.documents)

        #expect(Set(finalDocuments.compactMap {
            $0.attributeValue(for: WalletCoreSearchAttributeKey.chain)
        }) == Set([ApiChain.ethereum.rawValue, ApiChain.base.rawValue]))
        #expect(await recorder.callCount == 2)
    }

    @Test
    func `failed address resolution retracts the optimistic result`() async throws {
        let recorder = WalletResolutionRecorder(result: .failure(WalletResolutionTestError.failed))
        let source = makeSource(recorder: recorder)

        let snapshots = try await collectWalletSnapshots(source.snapshots(
            for: UniversalSearchQuery(address),
            context: context
        ))

        #expect(snapshots.count == 2)
        #expect(snapshots.first?.documents.count == 1)
        #expect(snapshots.last?.documents.isEmpty == true)
    }

    private func makeSource(
        recorder: WalletResolutionRecorder,
        supportedChains: [ApiChain] = ApiChain.allCases,
        knownWalletIdentifiers: Set<String> = []
    ) -> WalletCoreWalletAddressQuerySource {
        WalletCoreWalletAddressQuerySource(
            inputLoader: { _ in
                WalletCoreWalletAddressSearchInput(
                    network: .mainnet,
                    supportedChains: supportedChains,
                    knownWalletIdentifiers: knownWalletIdentifiers
                )
            },
            resolver: { chain, network, input in
                try await recorder.resolve(
                    chain: chain,
                    network: network,
                    input: input
                )
            },
            clock: { Date(timeIntervalSince1970: 42) }
        )
    }
}

private enum WalletResolutionTestError: Error, Sendable {
    case failed
}

private actor WalletResolutionRecorder {
    enum Result: Sendable {
        case success(WalletCoreWalletAddressResolution)
        case failure(any Error & Sendable)
    }

    private let result: Result
    private(set) var callCount = 0

    init(result: Result) {
        self.result = result
    }

    func resolve(
        chain: ApiChain,
        network: ApiNetwork,
        input: String
    ) async throws -> WalletCoreWalletAddressResolution {
        callCount += 1
        switch result {
        case .success(let resolution):
            return resolution
        case .failure(let error):
            throw error
        }
    }
}

private func collectWalletSnapshots(
    _ stream: AsyncThrowingStream<UniversalSearchSourceSnapshot, Error>
) async throws -> [UniversalSearchSourceSnapshot] {
    var snapshots: [UniversalSearchSourceSnapshot] = []
    for try await snapshot in stream {
        snapshots.append(snapshot)
    }
    return snapshots
}
