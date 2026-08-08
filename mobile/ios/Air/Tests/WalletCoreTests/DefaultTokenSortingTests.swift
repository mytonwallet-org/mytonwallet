import Testing
import WalletCore
import WalletContext

@Suite("Default Token Sorting")
struct DefaultTokenSortingTests {
    @Test
    func `empty multichain wallet keeps all native tokens in default order`() {
        let account = makeAccount(chains: ApiChain.allCases)
        let defaultSlugs = ApiToken.defaultSlugs(forNetwork: .mainnet, account: account)
        let tokenBalances = [
            MTokenBalance(tokenSlug: ROBINHOOD_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: MONAD_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: ARBITRUM_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: AVALANCHE_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: POLYGON_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: BNB_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: BASE_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: TRX_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: HYPERLIQUID_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: SOLANA_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: ETH_SLUG, balance: 0, isStaking: false),
        ]

        #expect(Array(defaultSlugs) == [
            ETH_SLUG,
            SOLANA_SLUG,
            HYPERLIQUID_SLUG,
            TONCOIN_SLUG,
            TRX_SLUG,
            BNB_SLUG,
            BASE_SLUG,
            ROBINHOOD_SLUG,
            MONAD_SLUG,
            ARBITRUM_SLUG,
            POLYGON_SLUG,
            AVALANCHE_SLUG,
        ])

        let sorted = MTokenBalance.sortedForBalanceData(
            tokenBalances: tokenBalances,
            balances: [:],
            defaultTokenSlugs: defaultSlugs,
            importedTokenSlugs: []
        )

        #expect(sorted.map(\.tokenSlug) == [
            ETH_SLUG,
            SOLANA_SLUG,
            HYPERLIQUID_SLUG,
            TONCOIN_SLUG,
            TRX_SLUG,
            BNB_SLUG,
            BASE_SLUG,
            ROBINHOOD_SLUG,
            MONAD_SLUG,
            ARBITRUM_SLUG,
            POLYGON_SLUG,
            AVALANCHE_SLUG,
        ])
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
