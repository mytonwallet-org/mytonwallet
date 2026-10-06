import Dependencies
import Foundation
import Testing
import UIComponents
@testable import UISwap
@testable import WalletCore
import WalletContext
import WalletResources

@Suite("Swap confirmation")
@MainActor
struct SwapConfirmationTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: [false, true])
    func `first fraction selection starts with primary loading appearance`(crosschain: Bool) async throws {
        let harness = Harness(crosschain: crosschain, defaultSellingAmount: nil)
        let model = harness.model
        let trade = TokenTradeModel(swap: model, direction: .sell, token: .TONCOIN, accountContext: model.input.$account)
        trade.isTokenAmount = true
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(trade.buttonConfiguration)
        #expect(!button.isEnabled)

        trade.useFraction(25)
        presenter.apply(trade.buttonConfiguration)
        #expect(trade.hasAmount)
        #expect(button.isEnabled)
        #expect(button.showLoading)
        #expect(!button.isUserInteractionEnabled)
        expectCannotConfirm(model)

        let amount = try #require(model.input.sellingTokenAmount).doubleValue
        try await harness.publishQuote(amount: amount)
        presenter.apply(trade.buttonConfiguration)
        #expect(button.isEnabled)
        #expect(!button.showLoading)
        #expect(button.isUserInteractionEnabled)
    }

    @Test(arguments: [false, true], [false, true])
    func `confirmation cancellation preserves ready appearance and the matching quote`(crosschain: Bool, isTrade: Bool) async throws {
        let harness = Harness(crosschain: crosschain)
        let model = harness.model
        let trade = TokenTradeModel(swap: model, direction: .sell, token: .TONCOIN, accountContext: model.input.$account)
        trade.isTokenAmount = true
        var input = TokenTradeAmountInput()
        input.set(1_000_000_000, decimals: 9)
        trade.userEditedInput(input)
        try await harness.publishQuote()
        let original = try #require(model.makeConfirmationSnapshot())
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        func apply() { presenter.apply(isTrade ? trade.buttonConfiguration : model.currentButtonConfiguration) }
        apply()
        #expect(button.isEnabled)
        #expect(button.isUserInteractionEnabled)

        model.setStage(.confirming)
        model.refreshBalances()
        apply()
        #expect(button.isEnabled)
        #expect(button.showLoading)
        #expect(!button.isUserInteractionEnabled)
        #expect(model.continueRoute() == nil)

        model.setStage(.editing)
        model.refreshBalances()
        apply()
        #expect(button.isEnabled)
        #expect(!button.showLoading)
        #expect(button.isUserInteractionEnabled)
        let restored = try #require(model.makeConfirmationSnapshot())
        #expect(restored.confirmation.selling.amount == original.confirmation.selling.amount)
        #expect(restored.estimateState.response == original.estimateState.response)
        try await harness.publishQuote()
    }

    @Test(arguments: [false, true])
    func `token trade retains the displayed fee and amount while a new quote loads`(crosschain: Bool) async throws {
        let harness = Harness(crosschain: crosschain)
        let model = harness.model
        let trade = TokenTradeModel(swap: model, direction: .sell, token: .TONCOIN, accountContext: model.input.$account)
        trade.isTokenAmount = true
        var amount = TokenTradeAmountInput()
        amount.set(1_000_000_000, decimals: 9)
        trade.userEditedInput(amount)
        try await harness.publishQuote()
        let oldFee = try #require(trade.feeText)
        let oldAmount = try #require(trade.methodAmountText)
        let oldRate = trade.rateText

        amount.set(2_000_000_000, decimals: 9)
        trade.userEditedInput(amount)
        #expect(trade.feeText == oldFee)
        #expect(trade.methodAmountText == oldAmount)
        #expect(trade.rateText == oldRate)
        #expect(trade.isMethodAmountStale)
        #expect(!trade.canContinue)
        expectCannotConfirm(model)

        model.estimate.synchronize()
        try await harness.publishQuote(amount: 2)
        #expect(trade.methodAmountText != oldAmount)
        #expect(!trade.isMethodAmountStale)

        trade.userEditedInput(TokenTradeAmountInput())
        #expect(trade.feeText == nil)
        #expect(trade.methodAmountText == nil)
        #expect(!trade.canContinue)
    }

    @Test
    func `changing the buying token preserves appearance but never the old executable quote`() async throws {
        let harness = Harness(crosschain: false)
        let model = harness.model
        try await harness.publishQuote()
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(model.currentButtonConfiguration)

        withDependencies {
            $0[_TokenStore.self] = TokenStore
        } operation: {
            model.input.userSelectedToken(ApiChain.ethereum.nativeToken, side: .buying)
        }
        presenter.apply(model.currentButtonConfiguration)

        #expect(button.isEnabled)
        #expect(button.showLoading)
        #expect(!button.isUserInteractionEnabled)
        #expect(button.attributedTitle(for: .normal)?.string.contains("ETH") == true)
        expectCannotConfirm(model)
    }

    @Test(arguments: [false, true])
    func `known insufficient balance ends optimistic loading before an estimate arrives`(crosschain: Bool) async throws {
        let harness = Harness(crosschain: crosschain)
        let model = harness.model
        try await harness.publishQuote()
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        presenter.apply(model.currentButtonConfiguration)

        model.input.sellingAmount = 2_000_000_000
        presenter.apply(model.currentButtonConfiguration)
        #expect(button.isEnabled)
        #expect(button.showLoading)
        #expect(!button.isUserInteractionEnabled)

        model.input.sellingAmount = 200_000_000_000
        presenter.apply(model.currentButtonConfiguration)
        #expect(!button.isEnabled)
        #expect(!button.showLoading)
        expectCannotConfirm(model)
    }

    @Test(arguments: [false, true])
    func `edited inputs cannot confirm the displayed quote`(crosschain: Bool) async throws {
        let harness = Harness(crosschain: crosschain)
        let model = harness.model
        try await harness.publishQuote()
        let original = try #require(model.makeConfirmationSnapshot())

        model.input.sellingAmount = 2_000_000_000
        #expect(model.estimate.displayed?.hasQuote == true)
        #expect(model.estimate.current == nil)
        expectCannotConfirm(model)

        model.estimate.synchronize()
        try await harness.publishQuote(amount: 2)
        let updated = try #require(model.makeConfirmationSnapshot())
        #expect(updated.confirmation.selling.amount == 2_000_000_000)
        #expect(updated.estimateState.response != original.estimateState.response)
        #expect(original.confirmation.selling.amount == 1_000_000_000)

        // Pausing stops loading, but cannot make an old quote confirmable.
        model.setStage(.externalAddress)
        model.commitSlippage(DEFAULT_SLIPPAGE + 1)
        #expect(!model.estimate.isLoading)
        expectCannotConfirm(model)
    }

    @Test(arguments: [false, true])
    func `rate limited refresh keeps only a matching quote usable`(crosschain: Bool) async throws {
        let harness = Harness(crosschain: crosschain)
        let model = harness.model
        try await harness.publishQuote()
        let original = try #require(model.makeConfirmationSnapshot())

        model.estimate.refresh()
        try await waitUntil { harness.probe.hasPendingLoad }
        #expect(model.estimate.isRefreshing)
        #expect(model.makeConfirmationSnapshot()?.estimateState.response == original.estimateState.response)

        try harness.probe.finish(.failure(rateLimitError))
        try await waitUntil { model.estimate.failure != nil }
        #expect(model.continueRoute() != nil)
        #expect(model.currentButtonConfiguration.isEnabled)
        #expect(model.makeConfirmationSnapshot()?.estimateState.response == original.estimateState.response)

        model.input.sellingAmount = 2_000_000_000
        model.estimate.synchronize()
        try await waitUntil { harness.probe.hasPendingLoad }
        try harness.probe.finish(.failure(rateLimitError))
        try await waitUntil { model.estimate.failure != nil }
        #expect(model.estimate.displayed?.hasQuote == true)
        expectCannotConfirm(model)

        model.estimate.retry()
        try await harness.publishQuote(amount: 2)
        #expect(model.makeConfirmationSnapshot()?.confirmation.selling.amount == 2_000_000_000)
    }

    @Test(arguments: [false, true])
    func `a rejected refresh and insufficient balance both block confirmation`(crosschain: Bool) async throws {
        let harness = Harness(crosschain: crosschain)
        let model = harness.model
        try await harness.publishQuote()
        #expect(model.continueRoute() != nil)

        harness.balances.replaceAll(byChain: [.ton: [TONCOIN_SLUG: 0]])
        expectCannotConfirm(model)
        harness.balances.replaceAll(byChain: [.ton: [TONCOIN_SLUG: 100_000_000_000]])
        #expect(model.makeConfirmationSnapshot() != nil)

        model.estimate.refresh()
        try await waitUntil { harness.probe.hasPendingLoad }
        try harness.probe.finish(.success(SwapEstimateUpdate(
            changedFrom: .selling,
            estimatedAmounts: nil,
            backendMaxAmount: nil,
            stateUpdate: SwapEstimateResult(changedFrom: .selling, response: nil, estimateIssue: .insufficientLiquidity)
        )))
        try await waitUntil { model.estimate.current?.draft.hasQuote == false }
        expectCannotConfirm(model)
    }

    @Test
    func `a balance change invalidates a max quote even while estimation is paused`() async throws {
        let harness = Harness(crosschain: false)
        let model = harness.model
        try await harness.publishQuote()
        model.input.isUsingMax = true
        model.estimate.synchronize()
        try await harness.publishQuote()
        model.setStage(.externalAddress)

        model.input.tokenBalance = 50_000_000_000
        #expect(model.estimate.displayed?.hasQuote == true)
        expectCannotConfirm(model)
    }
}

@MainActor private func expectCannotConfirm(_ model: SwapModel) {
    #expect(!model.currentButtonConfiguration.isEnabled)
    #expect(model.continueRoute() == nil)
    #expect(model.makeConfirmationSnapshot() == nil)
}

private let rateLimitError = SdkError.apiReturnedError(error: "Requests limit exceeded", data: "")

@MainActor private final class Harness {
    let probe = EstimateProbe()
    private let delegate = Delegate()
    let crosschain: Bool
    let balances: AccountBalances
    let model: SwapModel

    init(crosschain: Bool, defaultSellingAmount: Double? = 1) {
        self.crosschain = crosschain
        let accountId = "swapconfirmation\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))-mainnet"
        let store = _BalancesStore.liveValue
        balances = store.for(accountId: accountId)
        balances.replaceAll(byChain: [.ton: [TONCOIN_SLUG: 100_000_000_000]])
        model = withDependencies {
            $0[_TokenStore.self] = TokenStore
            $0[_BalancesStore.self] = store
        } operation: { [probe, delegate] in
            SwapModel(
                delegate: delegate,
                defaults: ApiSwapDefaults(tokenIn: .TONCOIN, tokenOut: crosschain ? ApiChain.ethereum.nativeToken : .TON_USDT),
                defaultSellingAmount: defaultSellingAmount,
                accountContext: AccountContext(source: .constant(MAccount(
                    id: accountId, title: nil, type: .mnemonic,
                    byChain: [.ton: AccountChain(address: "ton-address"), .ethereum: AccountChain(address: "eth-address")]
                ))),
                estimateLoader: { [probe] request, _ in try await probe.load(request) }
            )
        }
        model.estimate.refreshInterval = nil
    }

    func publishQuote(amount: Double = 1) async throws {
        try await waitUntil { self.probe.hasPendingLoad }
        try probe.finish(.success(quote(crosschain: crosschain, amount: amount)))
        try await waitUntil { self.model.estimate.current?.draft.hasQuote == true }
        // The model adjusts the production backoff interval after publishing.
        model.estimate.refreshInterval = nil
    }
}

@MainActor private final class Delegate: SwapModelDelegate {
    func executeSwapCommand(_ command: SwapCommand) {}
}

@MainActor private final class EstimateProbe {
    private var continuation: CheckedContinuation<SwapEstimateUpdate, any Error>?
    var hasPendingLoad: Bool { continuation != nil }

    func load(_ request: SwapEstimateRequest) async throws -> SwapEstimateUpdate {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(_ result: Result<SwapEstimateUpdate, any Error>) throws {
        let pending = try #require(continuation)
        continuation = nil
        pending.resume(with: result)
    }
}

private func quote(crosschain: Bool, amount: Double) throws -> SwapEstimateUpdate {
    var payload: [String: Any] = [
        "route": crosschain ? "cex" : "dex", "from": TONCOIN_SLUG,
        "to": crosschain ? ETH_SLUG : TON_USDT_SLUG,
        "fromAmount": String(amount), "toAmount": String(amount * 5), "swapFee": "0",
        "networkFee": "0.01", "realNetworkFee": "0.01", "dieselStatus": DieselStatus.notAvailable.rawValue
    ]
    if crosschain {
        payload.merge(["cexLabel": "changelly", "fromMin": "0.1", "fromMax": "1000"]) { _, new in new }
    } else {
        payload.merge([
            "toMinAmount": String(amount * 4.9), "impact": 0, "swapFeePercent": 0,
            "ourFee": "0", "ourFeePercent": 0
        ]) { _, new in new }
    }
    var response = try JSONDecoder().decode(ApiSwapEstimateResponse.self, from: JSONSerialization.data(withJSONObject: payload))
    if case .cex(var estimate) = response {
        estimate.isEnoughNative = true
        response = .cex(estimate)
    }
    return SwapEstimateUpdate(
        changedFrom: .selling,
        estimatedAmounts: .init(changedFrom: .selling, fromAmount: MDouble(amount), toAmount: MDouble(amount * 5)),
        backendMaxAmount: nil,
        stateUpdate: SwapEstimateResult(changedFrom: .selling, response: response)
    )
}

@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
        try #require(ContinuousClock.now < deadline, "Timed out waiting for swap estimate")
        try await Task.sleep(for: .milliseconds(5))
    }
}
