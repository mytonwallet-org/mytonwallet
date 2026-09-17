import Testing
import WalletContext
@testable import WalletCore

@Suite("Chain Token Visibility")
struct ChainTokenVisibilityTests {
    private let chains: [ApiChain] = [.ton, .ethereum, .solana]

    @Test(arguments: [false, true])
    func `dust and unpriced tokens follow the wallet token setting`(hidesTokensWithNoCost: Bool) {
        let visible = visibleChains(
            walletTokens: [
                token(TON_USDT_SLUG, balance: 1_000_000),
                token(ETH_USDT_MAINNET_SLUG, balance: 1),
                token(SOLANA_SLUG, balance: 1_000_000),
            ],
            hidesTokensWithNoCost: hidesTokensWithNoCost
        )

        #expect(visible == (hidesTokensWithNoCost ? [.ton] : Set(chains)))
    }

    @Test(arguments: [9_999, 10_000, 10_001])
    func `chain eligibility matches the wallet token cent boundary`(balance: Int) {
        let visible = visibleChains(walletTokens: [
            token(TON_USDT_SLUG, balance: 1_000_000),
            token(ETH_USDT_MAINNET_SLUG, balance: BigInt(balance)),
        ])

        #expect(visible == (balance > 10_000 ? [.ton, .ethereum] : [.ton]))
    }

    @Test(arguments: [false, true])
    func `all filtered balances use the empty wallet fallback`(isGramWallet: Bool) {
        let visible = visibleChains(
            walletTokens: [
                token(ETH_USDT_MAINNET_SLUG, balance: 1),
                token("solana-spam", balance: 1_000_000),
            ],
            isGramWallet: isGramWallet
        )

        #expect(visible == (isGramWallet ? [.ton] : Set(chains)))
    }

    @Test
    func `an empty wallet shows all account chains`() {
        #expect(visibleChains(walletTokens: []) == Set(chains))
    }

    @Test(arguments: [false, true])
    func `manually hidden wallet tokens do not enable their chain`(hidesTokensWithNoCost: Bool) {
        var preferences = MAssetsAndActivityData.empty
        preferences.saveTokenHidden(slug: ETH_USDT_MAINNET_SLUG, isStaking: false, isHidden: true)

        let visible = visibleChains(
            walletTokens: [
                token(TON_USDT_SLUG, balance: 1_000_000),
                token(ETH_USDT_MAINNET_SLUG, balance: 1_000_000),
            ],
            preferences: preferences,
            hidesTokensWithNoCost: hidesTokensWithNoCost
        )

        #expect(visible == [.ton])
    }

    @Test
    func `imported dust keeps the same exemption as the wallet token list`() {
        var preferences = MAssetsAndActivityData.empty
        preferences.saveImportedToken(slug: ETH_USDT_MAINNET_SLUG)

        let visible = visibleChains(
            walletTokens: [
                token(TON_USDT_SLUG, balance: 1_000_000),
                token(ETH_USDT_MAINNET_SLUG, balance: 1),
            ],
            preferences: preferences
        )

        #expect(visible == [.ton, .ethereum])
    }

    @Test(arguments: [false, true])
    func `staking follows wallet visibility including the low value exemption`(isHidden: Bool) {
        var preferences = MAssetsAndActivityData.empty
        preferences.saveTokenHidden(slug: TONCOIN_SLUG, isStaking: true, isHidden: isHidden)

        let visible = visibleChains(
            walletTokens: [token(ETH_USDT_MAINNET_SLUG, balance: 1_000_000)],
            walletStaked: [MTokenBalance(tokenSlug: TONCOIN_SLUG, balance: 1, isStaking: true)],
            preferences: preferences
        )

        #expect(visible == (isHidden ? [.ethereum] : [.ton, .ethereum]))
    }

    @Test
    func `zero balance visible tokens do not enable additional chains`() {
        let visible = visibleChains(
            walletTokens: [
                token(TON_USDT_SLUG, balance: 1_000_000),
                token(ETH_USDT_MAINNET_SLUG, balance: 0),
            ],
            hidesTokensWithNoCost: false
        )

        #expect(visible == [.ton])
    }

    private func token(_ slug: String, balance: BigInt) -> MTokenBalance {
        MTokenBalance(tokenSlug: slug, balance: balance, isStaking: false)
    }

    private func visibleChains(
        walletTokens: [MTokenBalance],
        walletStaked: [MTokenBalance] = [],
        preferences: MAssetsAndActivityData = .empty,
        hidesTokensWithNoCost: Bool = true,
        isGramWallet: Bool = false
    ) -> Set<ApiChain> {
        let account = MAccount(
            id: "chain-token-visibility-mainnet",
            title: nil,
            type: .mnemonic,
            byChain: Dictionary(uniqueKeysWithValues: chains.map { ($0, AccountChain(address: "\($0.rawValue)-address")) })
        )
        let presentation = MTokenBalance.presentationForUI(
            walletTokens: walletTokens,
            walletStaked: walletStaked,
            account: account,
            assetsAndActivityData: preferences,
            hidesTokensWithNoCost: hidesTokensWithNoCost
        )

        return MChainDisplayConfiguration.automaticallyVisibleChains(
            defaultOrder: chains,
            visibleTokenBalances: presentation.visible,
            isGramWallet: isGramWallet
        )
    }
}
