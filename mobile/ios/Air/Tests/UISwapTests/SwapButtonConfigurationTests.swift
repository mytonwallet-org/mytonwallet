import Dependencies
import Testing
@testable import UISwap
import WalletCore

@Suite("Swap Button Configuration")
struct SwapButtonConfigurationTests {
    @Test @MainActor
    func `submission stays busy through balance updates and restores editing afterward`() {
        withDependencies {
            $0[_TokenStore.self] = TokenStore
            $0[_BalancesStore.self] = .liveValue
        } operation: {
            let delegate = ButtonRecorder()
            let account = MAccount(id: "swap-progress-mainnet", title: nil, type: .mnemonic,
                                   byChain: [.ton: .init(address: "sender")])
            let model = SwapModel(
                delegate: delegate,
                defaults: .init(tokenIn: .TONCOIN, tokenOut: .TON_USDT),
                defaultSellingAmount: nil,
                accountContext: AccountContext(source: .constant(account))
            )
            model.refreshBalances()
            let editing = delegate.configuration
            #expect(editing != nil)

            model.setStage(.confirming)
            #expect(delegate.configuration?.showLoading == true)
            #expect(delegate.configuration?.isEnabled == false)
            #expect(model.continueRoute() == nil)

            model.refreshBalances()
            #expect(delegate.configuration?.showLoading == true)
            #expect(delegate.configuration?.isEnabled == false)

            model.setStage(.editing)
            model.refreshBalances()
            #expect(delegate.configuration?.showLoading == false)
            #expect(delegate.configuration?.isEnabled == editing?.isEnabled)
        }
    }

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

@MainActor
private final class ButtonRecorder: SwapModelDelegate {
    var configuration: SwapButtonConfiguration?
    func applyButtonConfiguration(_ config: SwapButtonConfiguration) { configuration = config }
    func executeSwapCommand(_ command: SwapCommand) {}
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
