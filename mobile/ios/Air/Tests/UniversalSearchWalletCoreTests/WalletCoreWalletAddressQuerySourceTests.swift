import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletCore
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

    @Test(arguments: ["mwme.ton", "  MWME.TON  ", "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"])
    func `known wallet identifier is left to the local wallet source`(identifier: String) async throws {
        let recorder = WalletResolutionRecorder(result: .success(.init(
            resolvedAddress: address
        )))
        let source = makeSource(
            recorder: recorder,
            knownAccounts: [makeAccount(domain: "mwme.ton")]
        )

        let snapshots = try await collectWalletSnapshots(source.snapshots(
            for: UniversalSearchQuery(identifier),
            context: context
        ))

        #expect(snapshots.isEmpty)
        #expect(await recorder.callCount == 0)
    }

    @Test(arguments: [false, true])
    func `domain resolving to a saved wallet keeps its identity and ownership`(isView: Bool) async throws {
        let account = makeAccount(isView: isView)
        let recorder = WalletResolutionRecorder(result: .success(.init(
            resolvedAddress: account.firstAddress
        )))
        let source = makeSource(recorder: recorder, knownAccounts: [account])
        let snapshots = try await collectWalletSnapshots(source.snapshots(
            for: UniversalSearchQuery("alias.ton"),
            context: context
        ))
        let resolved = try #require(snapshots.last)
        let document = try #require(resolved.documents.first)

        #expect(snapshots.count == 2)
        #expect(snapshots.first?.documents.first?.attributeValue(
            for: WalletCoreSearchAttributeKey.isResolvingDomain
        ) == "true")
        #expect(document.id == SearchEntityID("wallet:\(account.id)"))
        #expect(document.attributeValue(for: WalletCoreSearchAttributeKey.accountID) == account.id)
        #expect(document.attributeValue(for: WalletCoreSearchAttributeKey.isResolvingDomain) == nil)
        #expect(document.signals.traits.contains(.owned))
        #expect(!document.signals.traits.contains(.external))
        #expect(document.signals.traits.contains(.viewOnly) == isView)
        #expect(await recorder.callCount == 1)

        let local = try await WalletCoreWalletSearchSource(loader: { _ in [account] }).snapshot(for: context)
        let documents = UniversalSearchCorpus(snapshots: [local, resolved]).documents()
        #expect(documents.count == 1)
        #expect(UniversalSearchEngine().search("alias.ton", in: documents).map(\.id) == [document.id])
        #expect(UniversalSearchEngine().search(account.displayName, in: documents).map(\.id) == [document.id])
    }

    @Test
    func `resolved domain prefers a saved wallet over a temporary wallet`() async throws {
        let account = makeAccount()
        var temporary = makeAccount(id: "temporary-mainnet", isView: true)
        temporary.isTemporary = true
        let recorder = WalletResolutionRecorder(result: .success(.init(resolvedAddress: account.firstAddress)))
        let snapshots = try await collectWalletSnapshots(makeSource(
            recorder: recorder,
            knownAccounts: [temporary, account]
        ).snapshots(for: UniversalSearchQuery("alias.ton"), context: context))

        #expect(snapshots.last?.documents.first?.attributeValue(
            for: WalletCoreSearchAttributeKey.accountID
        ) == account.id)
    }

    @Test(arguments: ["network", "chain", "address", "temporary", "address-case"])
    func `unrelated accounts do not capture a resolved domain`(mismatch: String) async throws {
        let resolvedAddress = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
        var account = makeAccount(
            id: mismatch == "network" ? "saved-testnet" : "saved-mainnet",
            address: mismatch == "address" ? address : resolvedAddress,
            chain: mismatch == "chain" ? .solana : .ton
        )
        if mismatch == "temporary" { account.isTemporary = true }
        if mismatch == "address-case" {
            account.byChain[ApiChain.ton.rawValue]?.address = resolvedAddress.lowercased()
        }
        let recorder = WalletResolutionRecorder(result: .success(.init(resolvedAddress: resolvedAddress)))
        let snapshots = try await collectWalletSnapshots(makeSource(
            recorder: recorder,
            knownAccounts: [account]
        ).snapshots(for: UniversalSearchQuery("alias.ton"), context: context))
        let document = try #require(snapshots.last?.documents.first)

        #expect(document.signals.traits.contains([.external, .viewOnly]))
        #expect(document.attributeValue(for: WalletCoreSearchAttributeKey.accountID) == nil)
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
        knownAccounts: [MAccount] = []
    ) -> WalletCoreWalletAddressQuerySource {
        WalletCoreWalletAddressQuerySource(
            inputLoader: { _ in
                WalletCoreWalletAddressSearchInput(
                    network: .mainnet,
                    supportedChains: supportedChains,
                    knownAccounts: knownAccounts
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

    private func makeAccount(
        id: String = "saved-mainnet",
        address: String = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c",
        domain: String? = nil,
        chain: ApiChain = .ton,
        isView: Bool = false
    ) -> MAccount {
        MAccount(
            id: id,
            title: "Saved Wallet",
            type: isView ? .view : .mnemonic,
            byChain: [chain: AccountChain(address: address, domain: domain)]
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
