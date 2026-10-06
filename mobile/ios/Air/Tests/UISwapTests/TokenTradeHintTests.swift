import Dependencies
import Foundation
import Testing
@testable import UISwap
@testable import WalletCore
import WalletContext
import WalletResources

@Suite("Buy/Sell hints")
@MainActor
struct TokenTradeHintTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: [TokenTradeDirection.buy, .sell])
    func `funding hints use Swap eligibility and disappear for card payments`(direction: TokenTradeDirection) {
        let model = makeTrade(direction: direction, funded: false)
        #expect(model.hint != nil)
        #expect(model.hint == model.swap.hint)
        model.cardCurrency = .USD
        #expect(model.hint == nil)
        #expect(model.displayImpactWarning == nil)
    }

    @Test(arguments: [TokenTradeDirection.buy, .sell])
    func `intermediate actions keep the amount and selected assets consistent`(direction: TokenTradeDirection) async throws {
        let response = try decode(["error": "Pair not found", "hint": ["type": "intermediate", "token": SOLANA_SLUG]])
        let model = makeTrade(direction: direction, response: response)
        try await waitForEstimate(model)
        let hint = try #require(model.hint)
        let originalAmount = model.typedTokenAmount
        model.performHintAction(hint)
        #expect(model.swap.input.buyingToken?.slug == SOLANA_SLUG)
        #expect(model.swap.input.sellingToken?.slug == TONCOIN_SLUG)
        #expect(!model.canContinue)
        if direction == .buy {
            #expect(model.token.slug == SOLANA_SLUG)
            #expect(!model.hasAmount)
            #expect(model.input.text.isEmpty)
        } else {
            #expect(model.token.slug == TONCOIN_SLUG)
            #expect(model.paymentToken?.slug == SOLANA_SLUG)
            #expect(model.typedTokenAmount == originalAmount)
            #expect(model.swap.input.sellingAmount == originalAmount.amount)
        }
        #expect(model.hint != hint)
    }

    @Test
    func `an old hint cannot change a new selection or card payment`() async throws {
        let response = try decode(["error": "Pair not found", "hint": ["type": "intermediate", "token": SOLANA_SLUG]])
        let model = makeTrade(direction: .sell, response: response)
        try await waitForEstimate(model)
        let hint = try #require(model.hint)
        model.cardCurrency = .USD
        model.performHintAction(hint)
        #expect(model.swap.input.buyingToken?.slug == TON_USDT_SLUG)
        model.cardCurrency = nil
        model.selectToken(ApiChain.ethereum.nativeToken)
        model.performHintAction(hint)
        #expect(model.swap.input.buyingToken?.slug == ApiChain.ethereum.nativeToken.slug)
    }

    @Test(arguments: [1.0, 20.0])
    func `price impact follows Swap thresholds and card payments hide it`(impact: Double) async throws {
        let response = try decode([
            "route": "dex", "from": TONCOIN_SLUG, "to": TON_USDT_SLUG,
            "fromAmount": "1", "toAmount": "5", "swapFee": "0", "toMinAmount": "4.9",
            "impact": impact, "dieselStatus": DieselStatus.notAvailable.rawValue,
            "networkFee": "0.01", "realNetworkFee": "0.01", "swapFeePercent": 0,
            "ourFee": "0", "ourFeePercent": 0
        ])
        let model = makeTrade(direction: .sell, response: response)
        try await waitForEstimate(model)
        #expect(model.displayImpactWarning == model.swap.displayImpactWarning)
        #expect((model.displayImpactWarning != nil) == (impact == 20))
        model.cardCurrency = .USD
        #expect(model.displayImpactWarning == nil)
    }
}

@MainActor
private func makeTrade(direction: TokenTradeDirection, funded: Bool = true, response: ApiSwapEstimateResponse? = nil) -> TokenTradeModel {
    let id = "trade-hints-\(UUID().uuidString)-mainnet"
    let store = _BalancesStore.liveValue
    store.for(accountId: id).replaceAll(byChain: [.ton: [TONCOIN_SLUG: funded ? 10_000_000_000 : 0]])
    return withDependencies {
        $0[_TokenStore.self] = TokenStore
        $0[_BalancesStore.self] = store
    } operation: {
        let context = AccountContext(source: .constant(MAccount(id: id, title: nil, type: .mnemonic, byChain: [
            .ton: .init(address: "ton-address"), .solana: .init(address: "solana-address"),
            .ethereum: .init(address: "ethereum-address")
        ])))
        let swap = SwapModel(delegate: HintDelegate.shared, defaults: .init(tokenIn: .TONCOIN, tokenOut: .TON_USDT),
                             defaultSellingAmount: nil, accountContext: context, estimateLoader: { request, _ in
            guard let response else { throw CancellationError() }
            return SwapEstimateUpdate(changedFrom: request.side, estimatedAmounts: nil, backendMaxAmount: nil,
                                      stateUpdate: SwapEstimateResult(changedFrom: request.side, response: response))
        })
        let model = TokenTradeModel(swap: swap, direction: direction, token: direction == .buy ? .TON_USDT : .TONCOIN,
                                    accountContext: context)
        model.isTokenAmount = true
        var input = TokenTradeAmountInput()
        input.set(TokenAmount.fromDouble(1, model.token).amount, decimals: model.token.decimals)
        model.userEditedInput(input)
        swap.estimate.synchronize()
        return model
    }
}

@MainActor private func waitForEstimate(_ model: TokenTradeModel) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while model.swap.estimate.current == nil {
        try #require(ContinuousClock.now < deadline)
        try await Task.sleep(for: .milliseconds(5))
    }
    model.swap.estimate.pause()
}

private func decode(_ payload: [String: Any]) throws -> ApiSwapEstimateResponse {
    try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: JSONSerialization.data(withJSONObject: payload))
}

@MainActor private final class HintDelegate: SwapModelDelegate {
    static let shared = HintDelegate()
    func executeSwapCommand(_ command: SwapCommand) {}
}
