import Foundation
import UniversalSearchCore
import WalletCore
import WalletCoreTypes

public struct WalletCoreWalletAddressSearchInput: Sendable {
    public let network: ApiNetwork
    public let supportedChains: [ApiChain]
    public let knownAccounts: [MAccount]

    public init(
        network: ApiNetwork,
        supportedChains: [ApiChain] = ApiChain.allCases,
        knownAccounts: [MAccount] = []
    ) {
        self.network = network
        self.supportedChains = supportedChains
        self.knownAccounts = knownAccounts.filter { $0.network == network }
    }
}

public struct WalletCoreWalletAddressResolution: Equatable, Sendable {
    public let addressName: String?
    public let resolvedAddress: String?
    public let error: String?

    public init(
        addressName: String? = nil,
        resolvedAddress: String? = nil,
        error: String? = nil
    ) {
        self.addressName = addressName
        self.resolvedAddress = resolvedAddress
        self.error = error
    }
}

public struct WalletCoreWalletAddressQuerySource: UniversalSearchQuerySource {
    private enum ResolutionOutcome: Sendable {
        case success(ApiChain, WalletCoreWalletAddressResolution)
        case failure(ApiChain)
    }

    public typealias InputLoader = @MainActor @Sendable (
        UniversalSearchContext
    ) -> WalletCoreWalletAddressSearchInput?
    public typealias Resolver = @Sendable (
        ApiChain,
        ApiNetwork,
        String
    ) async throws -> WalletCoreWalletAddressResolution

    public static let id = SearchSourceID("wallet-core:wallet-address-query")

    public let sourceID = Self.id
    private let inputLoader: InputLoader
    private let resolver: Resolver
    private let clock: @Sendable () -> Date

    public init(
        inputLoader: @escaping InputLoader,
        resolver: @escaping Resolver,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.inputLoader = inputLoader
        self.resolver = resolver
        self.clock = clock
    }

    public init() {
        self.init(
            inputLoader: Self.loadLiveInput,
            resolver: { chain, network, input in
                let info = try await Api.getAddressInfo(
                    chain: chain,
                    network: network,
                    address: input
                )
                return WalletCoreWalletAddressResolution(
                    addressName: info.addressName,
                    resolvedAddress: info.resolvedAddress,
                    error: info.error
                )
            }
        )
    }

    public func snapshots(
        for query: UniversalSearchQuery,
        context: UniversalSearchContext
    ) -> AsyncThrowingStream<UniversalSearchSourceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let searchInput = await inputLoader(context) else {
                    continuation.finish()
                    return
                }

                let input = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let chains = Self.candidateChains(
                    for: input,
                    chains: searchInput.supportedChains
                )
                let knownIdentifiers = searchInput.knownAccounts
                    .flatMap(\.orderedChains)
                    .flatMap { _, info in [info.address, info.domain].compactMap { $0 } }
                    .map(Self.normalized)
                guard !knownIdentifiers.contains(Self.normalized(input)),
                      !chains.isEmpty else {
                    continuation.finish()
                    return
                }

                var documentsByChain: [ApiChain: SearchDocument] = [:]
                for chain in chains {
                    let isDomain = chain.isValidDomain(input)
                    documentsByChain[chain] = document(
                        input: input,
                        address: isDomain ? nil : input,
                        addressName: nil,
                        domain: isDomain ? input : nil,
                        chain: chain,
                        network: searchInput.network,
                        isResolvingDomain: isDomain
                    )
                }
                var lastDocuments = Self.orderedDocuments(
                    documentsByChain,
                    chains: chains
                )
                if !lastDocuments.isEmpty {
                    continuation.yield(snapshot(
                        documents: lastDocuments,
                        input: input,
                        chains: chains,
                        network: searchInput.network
                    ))
                }

                await withTaskGroup(of: ResolutionOutcome.self) { group in
                    for chain in chains {
                        group.addTask {
                            do {
                                return .success(
                                    chain,
                                    try await resolver(chain, searchInput.network, input)
                                )
                            } catch {
                                return .failure(chain)
                            }
                        }
                    }

                    for await outcome in group {
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            break
                        }
                        switch outcome {
                        case .success(let chain, let resolution):
                            let isDomain = chain.isValidDomain(input)
                            let resolvedAddress = Self.nonEmpty(resolution.resolvedAddress)
                                ?? (isDomain ? nil : input)
                            if resolution.error == nil, let resolvedAddress {
                                documentsByChain[chain] = document(
                                    input: input,
                                    address: resolvedAddress,
                                    addressName: Self.nonEmpty(resolution.addressName),
                                    domain: isDomain ? input : nil,
                                    chain: chain,
                                    network: searchInput.network,
                                    knownAccounts: searchInput.knownAccounts
                                )
                            } else {
                                documentsByChain.removeValue(forKey: chain)
                            }
                        case .failure(let chain):
                            documentsByChain.removeValue(forKey: chain)
                        }

                        let documents = Self.orderedDocuments(
                            documentsByChain,
                            chains: chains
                        )
                        guard documents != lastDocuments else { continue }
                        lastDocuments = documents
                        continuation.yield(snapshot(
                            documents: documents,
                            input: input,
                            chains: chains,
                            network: searchInput.network
                        ))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public static func candidateChains(
        for addressOrDomain: String,
        chains: [ApiChain] = ApiChain.allCases
    ) -> [ApiChain] {
        chains.filter { $0.isValidAddressOrDomain(addressOrDomain) }
    }

    private func document(
        input: String,
        address: String?,
        addressName: String?,
        domain: String?,
        chain: ApiChain,
        network: ApiNetwork,
        knownAccounts: [MAccount] = [],
        isResolvingDomain: Bool = false
    ) -> SearchDocument {
        if let address,
           let account = knownAccounts.first(where: { account in
               guard !account.isTemporaryView,
                     let info = account.getChainInfo(chain: chain) else { return false }
               let matchesDomain = domain.map { Self.normalized(info.domain ?? "") == Self.normalized($0) } ?? false
               let knownAddress = chain.normalizeAddress(info.address)
               let resolvedAddress = chain.normalizeAddress(address)
               let matchesAddress = chain.isEvm
                   ? knownAddress.caseInsensitiveCompare(resolvedAddress) == .orderedSame
                   : knownAddress == resolvedAddress
               return matchesDomain || matchesAddress
           }),
           let document = WalletCoreWalletSearchSource.documents(accounts: [account]).first {
            return SearchDocument(
                id: document.id,
                kind: document.kind,
                fields: document.fields + makeSearchFields([
                    (input, domain == nil ? .address : .domain, .exact),
                ]),
                matchRequirement: document.matchRequirement,
                attributes: document.attributes,
                signals: document.signals
            )
        }

        return SearchDocument(
            id: SearchEntityID(
                "wallet:external:\(network.rawValue):\(chain.rawValue):\(Self.normalized(input))"
            ),
            kind: .wallet,
            fields: makeSearchFields([
                (addressName, .title, .text),
                (domain, .domain, .exact),
                (domain == nil ? input : nil, .address, .exact),
                (address, .address, .exact),
            ]),
            matchRequirement: .exactIdentifier,
            attributes: makeSearchAttributes([
                (WalletCoreSearchAttributeKey.address, address),
                (WalletCoreSearchAttributeKey.addressName, addressName),
                (WalletCoreSearchAttributeKey.chain, chain.rawValue),
                (WalletCoreSearchAttributeKey.domain, domain),
                (WalletCoreSearchAttributeKey.inputAddressOrDomain, input),
                (WalletCoreSearchAttributeKey.isResolvingDomain, isResolvingDomain ? "true" : nil),
                (WalletCoreSearchAttributeKey.network, network.rawValue),
            ]),
            signals: SearchSignals(traits: [.external, .viewOnly])
        )
    }

    private func snapshot(
        documents: [SearchDocument],
        input: String,
        chains: [ApiChain],
        network: ApiNetwork
    ) -> UniversalSearchSourceSnapshot {
        UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            // Keep the resolved domain alias when merging with the local wallet document.
            authority: WalletCoreSearchSourceAuthority.local + 1,
            revision: "\(network.rawValue):\(chains.map(\.rawValue).joined(separator: ",")):\(Self.normalized(input))",
            generatedAt: clock(),
            documents: documents
        )
    }

    private static func orderedDocuments(
        _ documentsByChain: [ApiChain: SearchDocument],
        chains: [ApiChain]
    ) -> [SearchDocument] {
        chains.compactMap { documentsByChain[$0] }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    @MainActor
    private static func loadLiveInput(
        context: UniversalSearchContext
    ) -> WalletCoreWalletAddressSearchInput? {
        guard let accountID = context.scopeID,
              let account = AccountStore.accountsById[accountID] else { return nil }
        let network = context.network.flatMap(ApiNetwork.init(rawValue:)) ?? account.network

        let accounts = AccountStore.orderedAccountIdsWithTemporary
            .compactMap { AccountStore.accountsById[$0] }
            .filter { $0.network == network }
        return WalletCoreWalletAddressSearchInput(
            network: network,
            supportedChains: ApiChain.allCases.filter { account.supports(chain: $0) },
            knownAccounts: accounts
        )
    }
}
