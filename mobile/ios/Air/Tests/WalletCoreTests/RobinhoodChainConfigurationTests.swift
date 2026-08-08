import Testing
import WalletContext
import WalletCoreTypes

@Suite("Robinhood Chain Configuration")
struct RobinhoodChainConfigurationTests {
    @Test
    func `robinhood raw value and native token match backend metadata`() {
        #expect(ApiChain(rawValue: "robinhood") == .robinhood)
        #expect(ApiChain.robinhood.rawValue == "robinhood")
        #expect(ApiChain.robinhood.nativeToken == .ROBINHOOD)
        #expect(ApiChain.robinhood.nativeToken.symbol == "ETH")
        #expect(ApiChain.robinhood.nativeToken.decimals == 18)
    }

    @Test
    func `robinhood configuration matches web configuration`() {
        #expect(ApiChain.robinhood.isEvm)
        #expect(ApiChain.robinhood.defaultDerivationPath == "m/44'/60'/0'/0/{index}")
        #expect(ApiChain.robinhood.addressRegex.matches(ApiChain.robinhood.feeCheckAddress))
        #expect(ApiChain.robinhood.buySwap.tokenInSlug == TON_USDT_SLUG)
        #expect(ApiChain.robinhood.buySwap.amountIn == "50")
        #expect(ApiChain.robinhood.defaultEnabledSlugs[.mainnet] == [ROBINHOOD_SLUG])
        #expect(ApiChain.robinhood.crosschainSwapSlugs == [ROBINHOOD_SLUG])
        #expect(ApiChain.robinhood.explorer.baseUrl[.mainnet]?.url == "https://robinscan.io/")
        #expect(ApiChain.robinhood.walletConnectChainIds[.mainnet] == 4663)
        #expect(ApiChain.robinhood.walletConnectChainIds[.testnet] == 46630)
    }
}
