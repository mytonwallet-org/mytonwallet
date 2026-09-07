import Testing
import WalletCore
import WalletContext

@Suite("Default Token Sorting")
struct DefaultTokenSortingTests {
    @Test
    func `empty multichain wallet keeps all native tokens in default order`() {
        let account = makeAccount(chains: ApiChain.allCases)
        let defaultSlugs = ApiToken.defaultSlugs(forNetwork: .mainnet, account: account)
        let tokenBalances = defaultSlugs.reversed().map {
            MTokenBalance(tokenSlug: $0, balance: 0, isStaking: false)
        }

        let sorted = MTokenBalance.sortedForBalanceData(
            tokenBalances: tokenBalances,
            balances: [:],
            defaultTokenSlugs: defaultSlugs,
            importedTokenSlugs: []
        )

        #expect(sorted.map(\.tokenSlug) == Array(defaultSlugs))
    }

    @Test
    func `empty ton wallet keeps ton before usdt`() {
        let account = makeAccount(chains: [.ton])
        let defaultSlugs = ApiToken.defaultSlugs(forNetwork: .mainnet, account: account)
        let tokenBalances = [
            MTokenBalance(tokenSlug: TON_USDT_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 0, isStaking: false),
        ]

        let sorted = MTokenBalance.sortedForBalanceData(
            tokenBalances: tokenBalances,
            balances: [:],
            defaultTokenSlugs: defaultSlugs,
            importedTokenSlugs: []
        )

        #expect(sorted.map(\.tokenSlug) == [TONCOIN_SLUG, TON_USDT_SLUG])
    }

    @Test
    func `empty wallet keeps default tokens before extra zero balance tokens`() {
        let account = makeAccount(chains: [.ton, .ethereum, .solana])
        let defaultSlugs = ApiToken.defaultSlugs(forNetwork: .mainnet, account: account)
        let tokenBalances = [
            MTokenBalance(tokenSlug: MYCOIN_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: SOLANA_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: ETH_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 0, isStaking: false),
        ]

        let sorted = MTokenBalance.sortedForBalanceData(
            tokenBalances: tokenBalances,
            balances: [:],
            defaultTokenSlugs: defaultSlugs,
            importedTokenSlugs: []
        )

        #expect(sorted.map(\.tokenSlug) == [ETH_SLUG, SOLANA_SLUG, TONCOIN_SLUG, MYCOIN_SLUG])
    }

    @Test
    func `shared presentation puts pinned tokens before higher value tokens`() {
        let account = makeAccount(chains: [.ton])
        let tokenBalances = [
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: TON_USDT_SLUG, balance: 1_000_000, isStaking: false),
            MTokenBalance(tokenSlug: TON_USDT_TESTNET_SLUG, balance: 2_000_000, isStaking: false),
        ]
        var preferences = MAssetsAndActivityData.empty
        preferences.saveTokenPinning(slug: TONCOIN_SLUG, isStaking: false, isPinned: true)

        let presentation = MTokenBalance.presentationForUI(
            walletTokens: tokenBalances,
            account: account,
            assetsAndActivityData: preferences,
            hidesTokensWithNoCost: false
        )

        #expect(presentation.visible.map(\.tokenSlug) == [
            TONCOIN_SLUG,
            TON_USDT_TESTNET_SLUG,
            TON_USDT_SLUG,
        ])
        #expect(presentation.hidden.isEmpty)
    }

    @Test
    func `shared presentation groups hidden tokens without changing their order`() {
        let account = makeAccount(chains: [.ton])
        let tokenBalances = [
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 1, isStaking: false),
            MTokenBalance(tokenSlug: TON_USDT_SLUG, balance: 1_000_000, isStaking: false),
            MTokenBalance(tokenSlug: TON_USDT_TESTNET_SLUG, balance: 1, isStaking: false),
        ]
        var preferences = MAssetsAndActivityData.empty
        preferences.saveTokenPinning(slug: TONCOIN_SLUG, isStaking: false, isPinned: true)
        preferences.saveTokenHidden(slug: TON_USDT_TESTNET_SLUG, isStaking: false, isHidden: true)

        let presentation = MTokenBalance.presentationForUI(
            walletTokens: tokenBalances,
            account: account,
            assetsAndActivityData: preferences,
            hidesTokensWithNoCost: true
        )

        #expect(presentation.visible.map(\.tokenSlug) == [TON_USDT_SLUG])
        #expect(presentation.hidden.map(\.tokenSlug) == [
            TONCOIN_SLUG,
            TON_USDT_TESTNET_SLUG,
        ])
    }

    private func makeAccount(chains: [ApiChain]) -> MAccount {
        MAccount(
            id: "default-token-sorting-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: Dictionary(uniqueKeysWithValues: chains.map { ($0, AccountChain(address: "\($0.rawValue)-address")) })
        )
    }
}
