import Foundation
import UniversalSearchCore
import WalletCore
import WalletCoreTypes

public struct WalletCoreTokenSearchInput: Sendable {
    public let account: MAccount?
    public let tokens: [ApiToken]
    public let balances: [MTokenBalance]
    public let trackedTokenSlugs: Set<String>

    public init(
        account: MAccount?,
        tokens: [ApiToken],
        balances: [MTokenBalance],
        trackedTokenSlugs: Set<String>
    ) {
        self.account = account
        self.tokens = tokens
        self.balances = balances
        self.trackedTokenSlugs = trackedTokenSlugs
    }
}

public struct WalletCoreTokenSearchSource: UniversalSearchSource {
    public typealias Loader = @Sendable (UniversalSearchContext) async throws -> WalletCoreTokenSearchInput

    public static let id = SearchSourceID("wallet-core:tokens")

    public let sourceID = Self.id
    private let loader: Loader
    private let clock: @Sendable () -> Date

    public init(
        loader: @escaping Loader,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.loader = loader
        self.clock = clock
    }

    public init() {
        self.init(loader: Self.loadLiveInput)
    }

    public func snapshot(
        for context: UniversalSearchContext
    ) async throws -> UniversalSearchSourceSnapshot {
        let input = try await loader(context)
        let documents = Self.documents(input: input)
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: WalletCoreSearchSourceAuthority.local,
            generatedAt: clock(),
            documents: documents
        )
    }

    public static func documents(input: WalletCoreTokenSearchInput) -> [SearchDocument] {
        guard let account = input.account else { return [] }

        return WalletCoreTokenSearchDocuments.documents(
            tokens: input.tokens.filter { account.supports(chain: $0.chain) },
            balances: input.balances,
            trackedTokenSlugs: input.trackedTokenSlugs
        )
    }

    private static func loadLiveInput(
        context: UniversalSearchContext
    ) async throws -> WalletCoreTokenSearchInput {
        guard let accountID = context.scopeID,
              let account = AccountStore.accountsById[accountID] else {
            return WalletCoreTokenSearchInput(
                account: nil,
                tokens: [],
                balances: [],
                trackedTokenSlugs: []
            )
        }

        var tokens = TokenStore.tokens
        for token in TokenStore.swapAssets ?? [] where tokens[token.slug] == nil {
            tokens[token.slug] = token
        }
        let walletTokensData = await MainActor.run {
            BalanceDataStore.walletTokensData(accountId: accountID)
        }
        let balances = walletTokensData?.allTokenBalances ?? _BalancesStore.liveValue
            .getAccountBalances(accountId: accountID)
            .map { slug, balance in
                MTokenBalance(tokenSlug: slug, balance: balance, isStaking: false)
            }
        let trackedTokenSlugs = AssetsAndActivityDataStore
            .data(accountId: accountID)?
            .importedSlugs ?? []

        return WalletCoreTokenSearchInput(
            account: account,
            tokens: Array(tokens.values),
            balances: balances,
            trackedTokenSlugs: trackedTokenSlugs
        )
    }
}
