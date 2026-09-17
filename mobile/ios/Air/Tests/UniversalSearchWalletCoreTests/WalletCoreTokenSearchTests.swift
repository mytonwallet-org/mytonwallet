import Foundation
import Testing
import UniversalSearchCore
import UniversalSearchWalletCore
import WalletCore
import WalletCoreTypes

@Suite("Shared token search")
struct WalletCoreTokenSearchTests {
    private let ethereumUSDT = token("ethereum-usdt", name: "Tether", symbol: "USDT", chain: .ethereum)
    private let tonUSDT = token("ton-usdt", name: "Tether", symbol: "USDT", chain: .ton)
    private let ether = token("ethereum", name: "Ethereum", symbol: "ETH", chain: .ethereum)

    @Test(arguments: ["usdt ethereum", "ethereum usdt", "usdt eth"])
    func `chain terms complete a token match without promoting chain-only results`(query: String) throws {
        let documents = WalletCoreTokenSearchDocuments.documents(
            tokens: [ether, tonUSDT, ethereumUSDT],
            balances: [MTokenBalance(tokenSlug: tonUSDT.slug, balance: 100, isStaking: false)],
            trackedTokenSlugs: []
        )
        let hits = UniversalSearchEngine().search(query, in: documents)

        #expect(hits.first?.id == WalletCoreTokenSearchDocuments.entityID(tokenSlug: ethereumUSDT.slug))
        let hit = try #require(hits.first)
        #expect(hit.match.matchedTermCount == 2)
        #expect(hit.match.totalTermCount == 2)
        #expect(hit.match.wordMatchCount == 2)
        #expect(hit.match.fieldKind == .symbol)
    }

    @Test(arguments: ["eth", "ethereum"])
    func `chain-only token matches stay weak`(query: String) throws {
        let chainOnly = token("ethereum-usdc", name: "USD Coin", symbol: "USDC", chain: .ethereum)
        let documents = WalletCoreTokenSearchDocuments.documents(
            tokens: [chainOnly, ether],
            balances: [MTokenBalance(tokenSlug: chainOnly.slug, balance: 100, isStaking: false)],
            trackedTokenSlugs: [chainOnly.slug]
        )
        let hits = UniversalSearchEngine().search(query, in: documents)

        #expect(hits.map(\.id) == [ether, chainOnly].map { WalletCoreTokenSearchDocuments.entityID(tokenSlug: $0.slug) })
        #expect(hits.last?.rank.relevanceBand == .weak)
    }

    @Test(arguments: ["eth", "usdt", "usdt eth", "ethereum usdt", "tethr"])
    func `picker and universal search produce the same token order`(query: String) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = WalletCoreSearchInteractionStore(userDefaults: defaults, storageKey: "test")
        let tokens = [ether, tonUSDT, ethereumUSDT]
        let balances = [MTokenBalance(tokenSlug: tonUSDT.slug, balance: 1, isStaking: false)]
        let account = MAccount(
            id: "wallet", title: "Wallet", type: .mnemonic,
            byChain: [.ton: AccountChain(address: "EQ-test"), .ethereum: AccountChain(address: "0x-test")]
        )
        let documents = WalletCoreTokenSearchSource.documents(input: .init(
            account: account, tokens: tokens, balances: balances, trackedTokenSlugs: [ether.slug]
        ))
        var search = WalletCoreTokenSearch(interactionStore: store)
        search.update(accountID: account.id, tokens: tokens, balances: balances, trackedTokenSlugs: [ether.slug])

        let expected = UniversalSearchEngine().search(query, in: documents).compactMap {
            $0.document.attributeValue(for: WalletCoreSearchAttributeKey.tokenSlug)
        }
        #expect(!expected.isEmpty)
        #expect(search.search(query) == expected)
    }

    @Test
    func `picker candidates include crosschain assets and deduplicate wallet and catalog entries`() {
        var search = WalletCoreTokenSearch()
        search.update(accountID: "ton-only", tokens: [ether, ether, tonUSDT], balances: [], trackedTokenSlugs: [])

        #expect(search.search("ethereum") == [ether.slug])
        #expect(search.search("").isEmpty)
        #expect(search.search("  ").isEmpty)
    }

    @Test
    func `updates remove ineligible tokens and refresh held-token ranking`() {
        var search = WalletCoreTokenSearch()
        search.update(accountID: "test", tokens: [tonUSDT, ethereumUSDT], balances: [], trackedTokenSlugs: [])
        #expect(search.search("usdt").first == ethereumUSDT.slug)

        search.update(
            accountID: "test", tokens: [tonUSDT, ethereumUSDT],
            balances: [MTokenBalance(tokenSlug: tonUSDT.slug, balance: 1, isStaking: false)], trackedTokenSlugs: []
        )
        #expect(search.search("usdt").first == tonUSDT.slug)

        search.update(accountID: "test", tokens: [ethereumUSDT], balances: [], trackedTokenSlugs: [])
        #expect(search.search("usdt") == [ethereumUSDT.slug])
    }

    @Test
    func `picker selections share account-scoped search history`() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = WalletCoreSearchInteractionStore(userDefaults: defaults, storageKey: "test")
        var search = WalletCoreTokenSearch(interactionStore: store)
        search.recordSelection(tokenSlug: tonUSDT.slug, accountID: "first")
        search.update(accountID: "first", tokens: [ether, tonUSDT, ethereumUSDT], balances: [], trackedTokenSlugs: [])
        #expect(search.search("usdt").first == tonUSDT.slug)
        #expect(store.records(scopeID: "first").first?.entityID == WalletCoreTokenSearchDocuments.entityID(tokenSlug: tonUSDT.slug))

        search.update(accountID: "second", tokens: [ether, tonUSDT, ethereumUSDT], balances: [], trackedTokenSlugs: [])
        #expect(search.search("usdt").first == ethereumUSDT.slug)
    }

    @Test
    func `full contract addresses match exactly`() {
        let address = "0x1234567890123456789012345678901234567890"
        var addressedToken = ethereumUSDT
        addressedToken.tokenAddress = address
        var search = WalletCoreTokenSearch()
        search.update(accountID: "test", tokens: [addressedToken, ether], balances: [], trackedTokenSlugs: [])

        #expect(search.search(address) == [addressedToken.slug])
        #expect(search.search(String(address.dropLast())).isEmpty)
    }
}

private func token(_ slug: String, name: String, symbol: String, chain: ApiChain) -> ApiToken {
    ApiToken(slug: slug, name: name, symbol: symbol, decimals: 6, chain: chain)
}
