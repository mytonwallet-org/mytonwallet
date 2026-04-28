import Testing
import WalletCore
import WalletContext

@Suite("Default Token Sorting")
struct DefaultTokenSortingTests {
    @Test
    func `empty multichain wallet keeps default token order`() {
        let account = makeAccount(chains: [.ton, .tron, .solana, .ethereum, .bnb, .hyperliquid])
        let defaultSlugs = ApiToken.defaultSlugs(forNetwork: .mainnet, account: account)
        let tokenBalances = [
            MTokenBalance(tokenSlug: BNB_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: HYPERLIQUID_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: TRX_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: SOLANA_SLUG, balance: 0, isStaking: false),
            MTokenBalance(tokenSlug: ETH_SLUG, balance: 0, isStaking: false),
        ]

        let sorted = MTokenBalance.sortedForBalanceData(
            tokenBalances: tokenBalances,
            balances: [:],
            defaultTokenSlugs: defaultSlugs,
            importedTokenSlugs: []
        )

        #expect(sorted.map(\.tokenSlug) == [
            ETH_SLUG,
            SOLANA_SLUG,
            TRX_SLUG,
            BNB_SLUG,
            TONCOIN_SLUG,
            HYPERLIQUID_SLUG,
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

    private func makeAccount(chains: [ApiChain]) -> MAccount {
        MAccount(
            id: "default-token-sorting-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: Dictionary(uniqueKeysWithValues: chains.map { ($0, AccountChain(address: "\($0.rawValue)-address")) })
        )
    }
}
