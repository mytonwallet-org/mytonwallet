import Foundation
import UniversalSearchCore
import WalletCore
import WalletCoreTypes

public struct WalletCoreTokenAddressSearchInput: Sendable {
    public let accountID: String
    public let supportedChains: [ApiChain]
    public let knownTokens: [ApiToken]

    public init(
        accountID: String,
        supportedChains: [ApiChain],
        knownTokens: [ApiToken]
    ) {
        self.accountID = accountID
        self.supportedChains = supportedChains
        self.knownTokens = knownTokens
    }
}

public struct WalletCoreTokenAddressQuerySource: UniversalSearchQuerySource {
    public typealias InputLoader = @MainActor @Sendable (
        UniversalSearchContext
    ) -> WalletCoreTokenAddressSearchInput?
    public typealias Fetcher = @Sendable (
        String,
        ApiChain,
        String
    ) async throws -> ApiToken

    public static let id = SearchSourceID("wallet-core:token-address-query")

    public let sourceID = Self.id
    private let registry: WalletCoreSearchEntityRegistry
    private let inputLoader: InputLoader
    private let fetcher: Fetcher
    private let clock: @Sendable () -> Date

    public init(
        registry: WalletCoreSearchEntityRegistry,
        inputLoader: @escaping InputLoader,
        fetcher: @escaping Fetcher,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.registry = registry
        self.inputLoader = inputLoader
        self.fetcher = fetcher
        self.clock = clock
    }

    public init(registry: WalletCoreSearchEntityRegistry) {
        self.init(
            registry: registry,
            inputLoader: Self.loadLiveInput,
            fetcher: Api.fetchToken
        )
    }

    public func snapshots(
        for query: UniversalSearchQuery,
        context: UniversalSearchContext
    ) -> AsyncThrowingStream<UniversalSearchSourceSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard let input = await inputLoader(context) else {
                    continuation.finish()
                    return
                }

                let address = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let chains = Self.candidateChains(
                    for: address,
                    supportedChains: input.supportedChains
                )
                guard !chains.isEmpty else {
                    continuation.finish()
                    return
                }

                let knownTokens = input.knownTokens.filter {
                    chains.contains($0.chain)
                        && Self.addressesEqual($0.tokenAddress, address, chain: $0.chain)
                }
                guard knownTokens.isEmpty else {
                    continuation.finish()
                    return
                }

                let cachedTokens = await registry.tokens(accountID: input.accountID).filter {
                    chains.contains($0.chain)
                        && Self.addressesEqual($0.tokenAddress, address, chain: $0.chain)
                }
                if !cachedTokens.isEmpty {
                    continuation.yield(snapshot(
                        tokens: cachedTokens,
                        address: address
                    ))
                    continuation.finish()
                    return
                }

                var discoveredBySlug: [String: ApiToken] = [:]
                await withTaskGroup(of: ApiToken?.self) { group in
                    for chain in chains {
                        group.addTask {
                            do {
                                var token = try await fetcher(input.accountID, chain, address)
                                guard token.chain == chain else { return nil }
                                if token.tokenAddress?.isEmpty != false {
                                    token.tokenAddress = address
                                }
                                guard Self.addressesEqual(
                                    token.tokenAddress,
                                    address,
                                    chain: chain
                                ) else {
                                    return nil
                                }
                                return token
                            } catch {
                                return nil
                            }
                        }
                    }

                    for await token in group {
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            break
                        }
                        guard let token else { continue }
                        discoveredBySlug[token.slug] = token
                        let tokens = discoveredBySlug.values.sorted { $0.slug < $1.slug }
                        await registry.store(tokens: tokens, accountID: input.accountID)
                        continuation.yield(snapshot(
                            tokens: tokens,
                            address: address
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
        for address: String,
        supportedChains: [ApiChain]
    ) -> [ApiChain] {
        let supported = Set(supportedChains)
        return ApiChain.allCases.filter {
            supported.contains($0)
                && $0.config.canImportTokens
                && $0.isValidAddress(address)
        }
    }

    private func snapshot(
        tokens: [ApiToken],
        address: String
    ) -> UniversalSearchSourceSnapshot {
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: 90,
            revision: address,
            generatedAt: clock(),
            documents: tokens.map {
                WalletCoreTokenSearchDocuments.document(token: $0)
            }
        )
    }

    private static func addressesEqual(
        _ candidate: String?,
        _ query: String,
        chain: ApiChain
    ) -> Bool {
        guard let candidate else { return false }
        if chain.isEvm {
            return candidate.caseInsensitiveCompare(query) == .orderedSame
        }
        return candidate == query
    }

    @MainActor
    private static func loadLiveInput(
        context: UniversalSearchContext
    ) -> WalletCoreTokenAddressSearchInput? {
        guard let accountID = context.scopeID,
              let account = AccountStore.accountsById[accountID] else {
            return nil
        }
        var tokens = TokenStore.tokens
        for token in TokenStore.swapAssets ?? [] where tokens[token.slug] == nil {
            tokens[token.slug] = token
        }
        return WalletCoreTokenAddressSearchInput(
            accountID: accountID,
            supportedChains: ApiChain.allCases.filter { account.supports(chain: $0) },
            knownTokens: Array(tokens.values)
        )
    }
}
