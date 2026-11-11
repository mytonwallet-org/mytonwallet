import Testing
import WalletContext
import WalletCore

@Suite("Stablecoin classification")
struct StablecoinClassificationTests {
    @Test
    func includesConfiguredUsdcAcrossChains() {
        let slugs = getStablecoinSlugs()
        for slug in [
            "arbitrum-0xaf88d065",
            SOLANA_USDC_MAINNET_SLUG,
            ETH_USDC_MAINNET_SLUG,
            BASE_USDC_MAINNET_SLUG,
            HYPERLIQUID_USDC_MAINNET_SLUG,
        ] {
            #expect(slugs.contains(slug))
        }
        #expect(ApiChain.arbitrum.usdcSlug[.mainnet] == "arbitrum-0xaf88d065")
        #expect(ApiChain.arbitrum.usdcSlug[.testnet] == nil)
    }

    @Test
    func includesUsdtOnBothNetworksWithoutMatchingUnconfiguredTokens() {
        let slugs = getStablecoinSlugs()
        #expect(slugs.contains(TON_USDT_SLUG))
        #expect(slugs.contains(TON_USDT_TESTNET_SLUG))
        #expect(slugs.contains(TRON_USDT_SLUG))
        #expect(slugs.contains(TRON_USDT_TESTNET_SLUG))
        #expect(!slugs.contains(""))
        #expect(!slugs.contains(TONCOIN_SLUG))
        #expect(!slugs.contains("arbitrum-unlisted-usdc"))
    }
}
