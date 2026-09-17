import Testing
import WalletCore
import WalletContext
@testable import UISend

@Suite("Token send automatic selection")
@MainActor
struct TokenSendSelectionTests {
    @Test("EVM addresses select the highest fiat balance across compatible chains")
    func highestCompatibleBalance() {
        var eth = ApiChain.ethereum.nativeToken
        eth.priceUsd = 2_000
        var bnb = ApiChain.bnb.nativeToken
        bnb.priceUsd = 500
        var ton = ApiChain.ton.nativeToken
        ton.priceUsd = 5
        let chains = ApiChain.allCases.filter {
            $0.isValidAddressOrDomain("0x1111111111111111111111111111111111111111")
        }
        let selected = TokenSendModel.preferredToken(
            tokens: [ton, eth, bnb],
            balances: [
                ton.slug: 1_000_000_000_000,
                eth.slug: 100_000_000_000_000_000,
                bnb.slug: 1_000_000_000_000_000_000,
            ],
            compatibleChains: chains
        )
        #expect(selected?.slug == bnb.slug)
    }

    @Test("a token on the same chain can outrank the native token and display order")
    func highestTokenBalance() {
        var eth = ApiChain.ethereum.nativeToken
        eth.priceUsd = 2_000
        let usdt = ApiToken(
            slug: "ethereum-usdt", name: "Tether", symbol: "USDT",
            decimals: 6, chain: .ethereum, priceUsd: 1
        )
        let selected = TokenSendModel.preferredToken(
            tokens: [eth, usdt],
            balances: [eth.slug: 100_000_000_000_000_000, usdt.slug: 500_000_000],
            compatibleChains: [.ethereum]
        )
        #expect(selected?.slug == usdt.slug)
    }

    @Test("unsupported chains are excluded and missing candidates allow fallback")
    func supportedChainsOnly() {
        let eth = ApiChain.ethereum.nativeToken
        let bnb = ApiChain.bnb.nativeToken
        #expect(TokenSendModel.preferredToken(
            tokens: [bnb, eth], balances: [:], compatibleChains: [.ethereum]
        )?.slug == eth.slug)
        #expect(TokenSendModel.preferredToken(
            tokens: [bnb], balances: [:], compatibleChains: [.ethereum]
        ) == nil)
    }
}
