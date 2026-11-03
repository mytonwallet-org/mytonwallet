import Dependencies
import Foundation
import Testing
@testable import UISwap
@testable import WalletCore
import WalletContext
import WalletResources

@Suite("Sell 100%")
@MainActor
struct TokenTradeMaxAmountTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test
    func `100% stays the maximum after picking another token to receive`() async throws {
        let balance = TokenAmount.fromDouble(10, .TONCOIN).amount
        let model = makeSale(balance: balance, response: try feeResponse())
        defer { model.swap.estimate.pause() }
        model.useFraction(25)
        try await waitForEstimate(model)
        let maximum = try #require(model.swap.input.maxAmount)
        try #require(maximum < balance)
        model.useFraction(100)

        model.selectToken(.MYCOIN)
        #expect(model.swap.input.isUsingMax)
        #expect(model.swap.estimate.request?.amount == .max(balance: balance))
        #expect(model.typedTokenAmount.amount == model.swap.input.sellingAmount)

        model.selectToken(.TON_USDT)
        #expect(model.swap.input.isUsingMax)
        #expect(model.swap.estimate.request?.amount == .max(balance: balance))
        #expect(model.typedTokenAmount.amount == model.swap.input.sellingAmount)
    }

    @Test
    func `100% for a card becomes the card maximum, while a larger typed amount stays an error`() async throws {
        let model = makeSale(balance: TokenAmount.fromDouble(3_000, .TONCOIN).amount)
        defer { model.swap.estimate.pause() }
        let cardMaximum = TokenAmount.fromDouble(try #require(Moonpay.Offramp.limitsBySlug[TONCOIN_SLUG]), .TONCOIN).amount
        model.useFraction(100)

        model.selectCard(.EUR)
        #expect(model.actionTitle == lang("Loading..."))
        #expect(!model.hasAmountError)
        await model.refreshCardMaximum()
        #expect(model.typedTokenAmount.amount == cardMaximum)
        #expect(!model.hasAmountError)
        #expect(model.canContinue)
        #expect(model.actionTitle == L10n.sellTokenViaProvider(token: model.token.symbol, provider: "MoonPay"))

        var input = TokenTradeAmountInput()
        input.set(cardMaximum + 1, decimals: model.token.decimals)
        model.userEditedInput(input)
        #expect(model.hasAmountError)
        #expect(!model.canContinue)
        #expect(model.actionTitle == lang("Insufficient Balance"))
    }

    @Test
    func `100% for a card stays the maximum after switching back to a token`() async throws {
        let balance = TokenAmount.fromDouble(3_000, .TONCOIN).amount
        let model = makeSale(balance: balance)
        defer { model.swap.estimate.pause() }
        model.selectCard(.EUR)
        await model.refreshCardMaximum()
        model.useFraction(100)

        model.selectToken(.MYCOIN)
        #expect(model.swap.input.isUsingMax)
        #expect(model.swap.estimate.request?.amount == .max(balance: balance))
        #expect(model.typedTokenAmount.amount == balance)
        #expect(model.input.amount(decimals: model.token.decimals) == balance)
    }
}

@MainActor
private func makeSale(balance: BigInt, response: ApiSwapEstimateResponse? = nil) -> TokenTradeModel {
    let id = "trade-max-\(UUID().uuidString)-mainnet"
    let store = _BalancesStore.liveValue
    store.for(accountId: id).replaceAll(byChain: [.ton: [TONCOIN_SLUG: balance]])
    return withDependencies {
        $0[_TokenStore.self] = TokenStore
        $0[_BalancesStore.self] = store
    } operation: {
        let context = AccountContext(source: .constant(MAccount(id: id, title: nil, type: .mnemonic,
                                                                byChain: [.ton: .init(address: "ton-address")])))
        let swap = SwapModel(delegate: MaxAmountDelegate.shared, defaults: .init(tokenIn: .TONCOIN, tokenOut: .TON_USDT),
                             defaultSellingAmount: nil, accountContext: context, estimateLoader: { request, _ in
            guard let response else { throw CancellationError() }
            return SwapEstimateUpdate(changedFrom: request.side, estimatedAmounts: nil, backendMaxAmount: nil,
                                      stateUpdate: SwapEstimateResult(changedFrom: request.side, response: response))
        })
        let model = TokenTradeModel(swap: swap, direction: .sell, token: .TONCOIN, accountContext: context)
        model.isTokenAmount = true
        return model
    }
}

/// A quote whose network fee lowers the swap maximum below the balance.
private func feeResponse() throws -> ApiSwapEstimateResponse {
    try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: JSONSerialization.data(withJSONObject: [
        "route": "dex", "from": TONCOIN_SLUG, "to": TON_USDT_SLUG,
        "fromAmount": "2.5", "toAmount": "12.5", "swapFee": "0", "toMinAmount": "12.4",
        "impact": 0.1, "dieselStatus": DieselStatus.notAvailable.rawValue,
        "networkFee": "0.1", "realNetworkFee": "0.05", "swapFeePercent": 0,
        "ourFee": "0", "ourFeePercent": 0
    ]))
}

/// The timeout counts 5 ms samples rather than wall time: on a busy machine the estimate and this wait share a stalled
/// main actor, and the time neither of them runs is not the estimate's to spend. Ten times the timeout in wall time
/// still ends a wait whose samples keep stalling.
@MainActor private func waitForEstimate(_ model: TokenTradeModel) async throws {
    let timeout = Duration.seconds(2), sampleInterval = Duration.milliseconds(5)
    var remainingSamples = Int((timeout / sampleInterval).rounded(.up))
    let deadline = ContinuousClock.now + timeout * 10
    while model.swap.estimate.current == nil {
        try #require(remainingSamples > 0 && ContinuousClock.now < deadline)
        remainingSamples -= 1
        try await Task.sleep(for: sampleInterval)
    }
    model.swap.estimate.pause()
}

@MainActor private final class MaxAmountDelegate: SwapModelDelegate {
    static let shared = MaxAmountDelegate()
    func executeSwapCommand(_ command: SwapCommand) {}
}
