import Dependencies
import Foundation
import UIKit
import Testing
import UIComponents
@testable import UISwap
@testable import WalletCore
import WalletContext
import WalletResources

@Suite("Buy/Sell quote lifecycle")
@MainActor
struct TokenTradeQuoteLifecycleTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: [TokenTradeDirection.buy, .sell])
    func `below minimum Max stops the spinner and keeps the same exact in request`(
        direction: TokenTradeDirection
    ) async throws {
        let probe = QuoteProbe()
        let model = makeTrade(direction: direction, probe: probe)
        defer {
            model.swap.estimate.pause()
            probe.cancel()
        }
        let host = UIViewController()
        let tradeView = TokenTradeView(model: model, selectMethod: {}, continueAction: {})
        host.view = tradeView
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        tradeView.layoutIfNeeded()
        let maximumButton = try #require(button(in: tradeView, identifier: "tokenTrade.fraction.100"))
        let tapPoint = maximumButton.convert(CGPoint(x: maximumButton.bounds.midX, y: maximumButton.bounds.midY), to: tradeView)
        #expect(tradeView.hitTest(tapPoint, with: nil) === maximumButton)
        model.useFraction(100)
        // Do not synchronize manually: exercise the same observation path as a Max tap.
        try await waitUntil { probe.requests.count == 1 }
        let request = try #require(probe.requests.first)
        #expect(request.side == .selling)
        #expect(request.amount == .max(balance: 29_786_803))
        #expect(model.swap.input.buyingAmountInputDisabled)
        #expect(model.swap.input.sellingAmount == 29_786_803)
        #expect(model.buttonConfiguration.showLoading)
        try await waitUntil { continueButton(in: host.view)?.showLoading == true }

        try await waitUntil { tradeView.amountField.inputText == model.input.text }
        let caret = try #require(tradeView.amountField.position(from: tradeView.amountField.beginningOfDocument, offset: 1))
        tradeView.amountField.selectedTextRange = tradeView.amountField.textRange(from: caret, to: caret)
        let response = try minimumResponse()
        probe.complete(SwapEstimateUpdate(
            changedFrom: .selling,
            estimatedAmounts: .init(changedFrom: .selling, fromAmount: response.fromAmount, toAmount: response.toAmount),
            backendMaxAmount: nil,
            stateUpdate: SwapEstimateResult(changedFrom: .selling, response: .cex(response))
        ))
        try await waitUntil { model.swap.estimate.current != nil }
        #expect(model.swap.estimate.current?.request == request)
        #expect(model.swap.estimate.request == request)
        #expect(model.swap.currentButtonState == .blocked(.minimumAmount(response.fromMin, .ETH_USDT_MAINNET)))
        #expect(!model.buttonConfiguration.showLoading)
        #expect(!model.canContinue)
        #expect(model.actionTitle == SwapIssue.minimumAmount(response.fromMin, .ETH_USDT_MAINNET).buttonTitle)
        try await waitUntil { continueButton(in: host.view)?.showLoading == false }
        let button = try #require(continueButton(in: host.view))
        #expect(!button.isEnabled)
        #expect(button.subviews.compactMap { $0 as? TokenTradeButtonTitleView }.first?.text == model.actionTitle)
        #expect(button.accessibilityLabel == model.actionTitle)

        // Compact sheets must keep the method row reachable as quote/layout updates arrive.
        tradeView.bounds.size.height = 480
        tradeView.setNeedsLayout()
        tradeView.layoutIfNeeded()
        let scroll = tradeView.scrollView
        let bottomOffset = max(0, scroll.contentSize.height - scroll.bounds.height)
        #expect(bottomOffset > 0)
        scroll.contentOffset.y = bottomOffset
        tradeView.setNeedsLayout()
        tradeView.layoutIfNeeded()
        #expect(scroll.contentOffset.y == bottomOffset)
        #expect(tradeView.methodButton.frame.maxY <= scroll.bounds.maxY)
        let selection = try #require(tradeView.amountField.selectedTextRange)
        #expect(tradeView.amountField.offset(from: tradeView.amountField.beginningOfDocument, to: selection.start) == 1)

        // Applying a zero output and the Max amount must not create a feedback loop.
        try await Task.sleep(for: .milliseconds(350))
        #expect(probe.requests.count == 1)
        #expect(!model.buttonConfiguration.showLoading)

        // A refresh of this same request keeps the known minimum visible.
        model.swap.estimate.refresh()
        try await waitUntil { probe.requests.count == 2 }
        #expect(probe.requests.last == request)
        #expect(model.swap.estimate.isRefreshing)
        #expect(!model.buttonConfiguration.showLoading)
        #expect(!button.showLoading)
        #expect(button.subviews.compactMap { $0 as? TokenTradeButtonTitleView }.first?.text == model.actionTitle)
        #expect(button.accessibilityLabel == model.actionTitle)
    }
}

@MainActor private final class QuoteProbe {
    var requests: [SwapEstimateRequest] = []
    private var pending: CheckedContinuation<SwapEstimateUpdate, any Error>?

    func load(_ request: SwapEstimateRequest) async throws -> SwapEstimateUpdate {
        requests.append(request)
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func complete(_ update: SwapEstimateUpdate) {
        pending?.resume(returning: update)
        pending = nil
    }

    func cancel() {
        pending?.resume(throwing: CancellationError())
        pending = nil
    }
}

@MainActor private func makeTrade(direction: TokenTradeDirection, probe: QuoteProbe) -> TokenTradeModel {
    let id = "trade-minimum-\(UUID().uuidString)-mainnet"
    let balances = _BalancesStore.liveValue
    balances.for(accountId: id).replaceAll(byChain: [.ethereum: [ETH_USDT_MAINNET_SLUG: 29_786_803]])
    return withDependencies {
        $0[_TokenStore.self] = TokenStore
        $0[_BalancesStore.self] = balances
    } operation: {
        let context = AccountContext(source: .constant(MAccount(
            id: id, title: nil, type: .mnemonic,
            byChain: [.ethereum: .init(address: "ethereum-address"), .ton: .init(address: "ton-address")]
        )))
        // Both assets have a deterministic USD price, so Max exercises the Buy conversion too.
        let swap = SwapModel(delegate: QuoteDelegate.shared,
                             defaults: .init(tokenIn: .ETH_USDT_MAINNET, tokenOut: .TON_USDT),
                             defaultSellingAmount: nil, accountContext: context,
                             estimateLoader: { request, _ in try await probe.load(request) })
        return TokenTradeModel(swap: swap, direction: direction,
                               token: direction == .buy ? .TON_USDT : .ETH_USDT_MAINNET,
                               accountContext: context)
    }
}

private func minimumResponse() throws -> ApiSwapCexEstimateResponse {
    try JSONDecoder().decode(ApiSwapCexEstimateResponse.self, from: JSONSerialization.data(withJSONObject: [
        "cexLabel": "changelly", "from": ETH_USDT_MAINNET_SLUG, "to": TON_USDT_SLUG,
        "fromAmount": "29.786803", "toAmount": "0", "fromMin": "30.03", "fromMax": "100000",
        "swapFee": "0"
    ]))
}

@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
        try #require(ContinuousClock.now < deadline)
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor private func button(in view: UIView, identifier: String) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityIdentifier == identifier { return button }
    return view.subviews.lazy.compactMap { button(in: $0, identifier: identifier) }.first
}

@MainActor private func continueButton(in view: UIView) -> WButton? {
    if let button = view as? WButton, button.accessibilityIdentifier == "tokenTrade.continue" { return button }
    return view.subviews.lazy.compactMap { continueButton(in: $0) }.first
}

@MainActor private final class QuoteDelegate: SwapModelDelegate {
    static let shared = QuoteDelegate()
    func executeSwapCommand(_ command: SwapCommand) {}
}
