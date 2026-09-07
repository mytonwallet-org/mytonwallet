import Testing
@testable import UISwap
import WalletCore

@Suite("Swap Button Configuration")
struct SwapButtonConfigurationTests {
    @Test
    func `swap title presentation ignores token details that do not change button text`() {
        let selling = token(slug: "toncoin", symbol: "TON", chain: .ton)
        var sellingWithUpdatedPrice = selling
        sellingWithUpdatedPrice.priceUsd = 4.2
        sellingWithUpdatedPrice.percentChange24h = -1.5
        let buying = token(slug: "tether-usdt", symbol: "USDT", chain: .ton)

        let first = SwapButtonConfiguration(
            title: .swap(selling, buying),
            isEnabled: false,
            showLoading: false
        )
        let second = SwapButtonConfiguration(
            title: .swap(sellingWithUpdatedPrice, buying),
            isEnabled: false,
            showLoading: false
        )

        #expect(first.hasSamePresentation(as: second))
    }

    @Test
    func `swap title presentation changes when displayed symbol changes`() {
        let selling = token(slug: "toncoin", symbol: "TON", chain: .ton)
        let buying = token(slug: "tether-usdt", symbol: "USDT", chain: .ton)
        let nextBuying = token(slug: "ethereum-eth", symbol: "ETH", chain: .ethereum)

        let first = SwapButtonConfiguration(
            title: .swap(selling, buying),
            isEnabled: false,
            showLoading: false
        )
        let second = SwapButtonConfiguration(
            title: .swap(selling, nextBuying),
            isEnabled: false,
            showLoading: false
        )

        #expect(!first.hasSamePresentation(as: second))
    }

}

private func token(slug: String, symbol: String, chain: ApiChain, decimals: Int = 9) -> ApiToken {
    ApiToken(
        slug: slug,
        name: symbol,
        symbol: symbol,
        decimals: decimals,
        chain: chain
    )
}
