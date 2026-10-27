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
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 1, isStaking: false),
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

    @Test(arguments: [false, true])
    func `priced holding hides empty defaults regardless of no cost setting`(hidesTokensWithNoCost: Bool) {
        let account = makeAccount(chains: [.ton, .solana])
        let defaultSlugs = ApiToken.defaultSlugs(forNetwork: .mainnet, account: account)
        var walletTokens = defaultSlugs.map {
            MTokenBalance(tokenSlug: $0, balance: 0, isStaking: false)
        }
        let fundedToken = MTokenBalance(tokenSlug: TON_USDT_SLUG, balance: 15_000, isStaking: false)
        let emptyNonDefaultToken = MTokenBalance(tokenSlug: MYCOIN_SLUG, balance: 0, isStaking: false)
        walletTokens.append(contentsOf: [fundedToken, emptyNonDefaultToken])

        #expect((fundedToken.toUsd ?? 0) > TINY_TRANSFER_MAX_COST)

        let presentation = MTokenBalance.presentationForUI(
            walletTokens: walletTokens,
            account: account,
            assetsAndActivityData: .empty,
            hidesTokensWithNoCost: hidesTokensWithNoCost
        )

        #expect(presentation.visible == (hidesTokensWithNoCost ? [fundedToken] : [fundedToken, emptyNonDefaultToken]))
        #expect(Set(presentation.hidden.map(\.tokenSlug)).isSuperset(of: defaultSlugs))
    }

    @Test(arguments: [false, true])
    func `dust and unpriced holdings keep defaults regardless of no cost setting`(hidesTokensWithNoCost: Bool) {
        let account = makeAccount(chains: [.ton, .solana])
        let walletTokens = [
            MTokenBalance(tokenSlug: TON_USDT_SLUG, balance: 9_999, isStaking: false),
            MTokenBalance(tokenSlug: TON_USDT_TESTNET_SLUG, balance: 9_999, isStaking: false),
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 10_000_000, isStaking: false),
        ]
        #expect(walletTokens.allSatisfy { ($0.toUsd ?? 0) < TINY_TRANSFER_MAX_COST })
        #expect(walletTokens.reduce(0) { $0 + ($1.toUsd ?? 0) } > TINY_TRANSFER_MAX_COST)

        let presentation = MTokenBalance.presentationForUI(
            walletTokens: walletTokens,
            walletStaked: [MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 1, isStaking: true)],
            account: account,
            assetsAndActivityData: .empty,
            hidesTokensWithNoCost: hidesTokensWithNoCost
        )

        let visibleWalletSlugs = Set(presentation.visible.filter { !$0.isStaking }.map(\.tokenSlug))
        #expect(visibleWalletSlugs.isSuperset(of: ApiToken.defaultSlugs(forNetwork: .mainnet, account: account)))
    }

    @Test(arguments: [false, true])
    func `empty wallet keeps defaults regardless of no cost setting`(hidesTokensWithNoCost: Bool) {
        let account = makeAccount(chains: [.ton, .solana])
        let presentation = MTokenBalance.presentationForUI(
            walletTokens: [],
            account: account,
            assetsAndActivityData: .empty,
            hidesTokensWithNoCost: hidesTokensWithNoCost
        )

        #expect(presentation.visible.map(\.tokenSlug) == Array(ApiToken.defaultSlugs(forNetwork: .mainnet, account: account)))
        #expect(presentation.hidden.isEmpty)
    }

    @Test(arguments: [false, true], [false, true])
    func `funded wallet respects imported and hidden tokens`(hidesTokensWithNoCost: Bool, isHidden: Bool) {
        let account = makeAccount(chains: [.ton, .solana])
        let walletTokens = [
            MTokenBalance(tokenSlug: TON_USDT_SLUG, balance: 15_000, isStaking: false),
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 0, isStaking: false),
        ]
        var preferences = MAssetsAndActivityData.empty
        preferences.saveImportedToken(slug: SOLANA_SLUG)
        preferences.saveTokenHidden(slug: SOLANA_SLUG, isStaking: false, isHidden: isHidden)

        let presentation = MTokenBalance.presentationForUI(
            walletTokens: walletTokens,
            account: account,
            assetsAndActivityData: preferences,
            hidesTokensWithNoCost: hidesTokensWithNoCost
        )

        #expect(presentation.visible.map(\.tokenSlug) == (isHidden ? [TON_USDT_SLUG] : [TON_USDT_SLUG, SOLANA_SLUG]))
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
