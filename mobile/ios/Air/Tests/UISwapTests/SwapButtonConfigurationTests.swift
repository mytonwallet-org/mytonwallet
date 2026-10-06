import Dependencies
import Testing
import UIComponents
@testable import UISwap
import WalletCore
import WalletResources

@Suite("Swap Button Configuration")
@MainActor
struct SwapButtonConfigurationTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test
    func `empty swap does not seed disabled appearance for the first estimate`() {
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        let model = SwapButtonModel()
        presenter.apply(model.configuration(for: .emptyAmount, sellingToken: .TONCOIN, buyingToken: .TON_USDT))
        #expect(!button.isEnabled)

        presenter.apply(model.configuration(for: .estimating(showContinue: false), sellingToken: .TONCOIN, buyingToken: .TON_USDT))
        #expect(button.isEnabled)
        #expect(button.showLoading)
        #expect(!button.isUserInteractionEnabled)
    }

    @Test
    func `submission stays busy through balance updates and restores editing afterward`() {
        withDependencies {
            $0[_TokenStore.self] = TokenStore
            $0[_BalancesStore.self] = .liveValue
        } operation: {
            let delegate = Delegate()
            let account = MAccount(id: "swap-progress-mainnet", title: nil, type: .mnemonic,
                                   byChain: [.ton: .init(address: "sender")])
            let model = SwapModel(
                delegate: delegate,
                defaults: .init(tokenIn: .TONCOIN, tokenOut: .TON_USDT),
                defaultSellingAmount: nil,
                accountContext: AccountContext(source: .constant(account))
            )
            model.refreshBalances()
            let editing = model.currentButtonConfiguration

            model.setStage(.confirming)
            #expect(model.currentButtonConfiguration.showLoading)
            #expect(!model.currentButtonConfiguration.isEnabled)
            #expect(model.continueRoute() == nil)

            model.refreshBalances()
            #expect(model.currentButtonConfiguration.showLoading)
            #expect(!model.currentButtonConfiguration.isEnabled)

            model.setStage(.editing)
            model.refreshBalances()
            #expect(!model.currentButtonConfiguration.showLoading)
            #expect(model.currentButtonConfiguration.isEnabled == editing.isEnabled)
        }
    }

    @Test
    func `swap title presentation ignores token details that do not change button text`() {
        let selling = token(slug: "toncoin", symbol: "TON", chain: .ton)
        var sellingWithUpdatedPrice = selling
        sellingWithUpdatedPrice.priceUsd = 4.2
        sellingWithUpdatedPrice.percentChange24h = -1.5
        let buying = token(slug: "tether-usdt", symbol: "USDT", chain: .ton)

        let first = SwapButtonModel().configuration(for: .waitingForEstimate, sellingToken: selling, buyingToken: buying)
        let second = SwapButtonModel().configuration(for: .waitingForEstimate, sellingToken: sellingWithUpdatedPrice, buyingToken: buying)

        #expect(first == second)
    }

    @Test
    func `swap title presentation changes when displayed symbol changes`() {
        let selling = token(slug: "toncoin", symbol: "TON", chain: .ton)
        let buying = token(slug: "tether-usdt", symbol: "USDT", chain: .ton)
        let nextBuying = token(slug: "ethereum-eth", symbol: "ETH", chain: .ethereum)

        let first = SwapButtonModel().configuration(for: .waitingForEstimate, sellingToken: selling, buyingToken: buying)
        let second = SwapButtonModel().configuration(for: .waitingForEstimate, sellingToken: selling, buyingToken: nextBuying)

        #expect(first != second)
    }

}

@MainActor private final class Delegate: SwapModelDelegate {
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
