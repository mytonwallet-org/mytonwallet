import Foundation
import Testing
import UIKit
import UIComponents
import WalletCore
import WalletContext
import WalletResources
@testable import UIToken

@Suite @MainActor
struct PerpsLeverageEditingTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test func leverageSelectionKeepsThePositionAmountAndRequiresAFreshReview() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: order()) { requests.append($0) }
        #expect(state.canSelectLeverage)
        state.selectLeverage(5)
        let change = try #require(requests.last)
        #expect(change.action == .leverageChanged)
        #expect(change.positionID == "wallet/btc")
        #expect(change.input.amount.text == "20")
        #expect(change.input.leverage == 5)
        #expect(state.isChangingLeverage)
        #expect(state.hasPositionChanges)
        #expect(!state.canReview)

        var response = order()
        response.input = change.input
        response.editingPosition?.change = .leverage
        response.status = .ready
        #expect(state.update(data: response, for: change))
        #expect(state.canReview)
        state.request(.review)
        #expect(requests.last?.input.leverage == 5)
        #expect(requests.last?.input.amount.text == "20")
    }

    @Test func typingAnAmountRestoresCurrentLeverageAndClearsItsPayment() throws {
        var data = order()
        data.input.leverage = 5
        data.input.leverageOnly = true
        data.editingPosition?.change = .leverage
        data.paymentAmount = "10.2"
        data.status = .ready
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.editAmount(.init(text: "30"))
        let request = try #require(requests.last)
        #expect(request.action == .amountChanged)
        #expect(request.input.leverage == 2)
        #expect(request.input.amount.text == "30")
        #expect(state.data.input.leverage == 2)
        #expect(state.data.paymentAmount == nil)
        #expect(state.data.editingPosition?.change == nil)
        #expect(!state.canSelectLeverage)
        #expect(!state.canReview)
    }

    @Test func resizingAndLeverageSelectionCannotBeCombined() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: order()) { requests.append($0) }
        state.editAmount(.init(text: "30"))
        state.selectLeverage(5)
        #expect(requests.count == 1)
        #expect(state.data.input.leverage == 2)
        state.request(.resetAmount)
        let reset = try #require(requests.last)
        #expect(state.update(data: order(), for: reset))
        #expect(state.canSelectLeverage)
        state.selectLeverage(5)
        state.request(.resetAmount)
        #expect(requests.last?.input.leverage == 2)
    }

    @Test func returningToCurrentLeverageRejectsAnOlderDepositEstimate() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: order()) { requests.append($0) }
        state.selectLeverage(5)
        let previous = try #require(requests.last)
        state.selectLeverage(2)
        let latest = try #require(requests.last)
        var stale = order()
        stale.input.leverage = 5
        stale.editingPosition?.change = .leverage
        stale.paymentAmount = "10.2"
        stale.status = .ready
        #expect(!state.update(data: stale, for: previous))
        #expect(state.update(data: order(), for: latest))
        #expect(state.data.input.leverage == 2)
        #expect(state.data.paymentAmount == nil)
        #expect(!state.hasPositionChanges)
        #expect(!state.canReview)
    }

    @Test(arguments: ["0", "10.2"])
    func leverageReviewAndPaymentUseTheBackendQuote(payment: String) throws {
        let quote = try quote(payment: payment)
        let asset = try asset()
        let review = PerpsSDKAdapter.review(quote, asset: asset)
        #expect(review.mode.operation == .leverage)
        #expect(review.positionID == "wallet/btc")
        #expect(review.paymentQuantity == payment)
        #expect(review.leverage == 5)
        #expect(review.mode.previous?.margin == .fromDouble(20, .USD))
        let state = PerpsOrderReviewState(data: review) { request in
            #expect(request.operation == .leverage)
            #expect(request.positionID == "wallet/btc")
        }
        #expect(state.canConfirm)
        state.confirm()
        #expect(!state.canConfirm)

        let option = PerpsSDKAdapter.leverageOption(quote)
        #expect(option.value == 5)
        #expect(option.paymentAmount == PerpsFormatting.quantity(payment, symbol: "USDC"))
        #expect(option.liquidationPrice == "≈ " + PerpsFormatting.money("80"))

        let account = MAccount(id: "wallet", title: "Wallet", type: .mnemonic,
                               byChain: [.arbitrum: AccountChain(address: "0x1234")])
        let data = PerpsSDKAdapter.order(asset: asset, account: account, side: .long,
                                        input: .init(amount: "20", leverage: 5), position: try position(), quote: quote)
        #expect(data.editingPosition?.change == .leverage)
        #expect(data.editingPosition?.currentLeverage == 2)
        #expect(data.input.leverage == 5)
        #expect(data.paymentAmount == payment)
        #expect(PerpsOrderState(data: data, onRequest: { _ in }).canReview)
    }

    @Test func leverageIntentIsExplicitAtTheSDKBoundary() throws {
        let draft = ApiPerpsDraft(assetId: "btc", side: "long", amount: "20", leverage: 5,
                                  editing: true, leverageOnly: true)
        let data = try JSONEncoder().encode(draft)
        let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["leverageOnly"] as? Bool == true)
        #expect(decoded["editing"] as? Bool == true)
        #expect(decoded["amount"] as? String == "20")
        #expect(decoded["leverage"] as? Int == 5)
    }

    @Test func editingSheetShowsTheQuotedDepositAlongsideLiquidation() async throws {
        var data = order()
        data.input.leverage = 5
        let controller = PerpsLeverageVC(data: data) { _ in }
        controller.loadEstimate = { leverage in
            [.init(value: leverage, liquidationPrice: "$80", paymentAmount: "10.2 USDC")]
        }
        controller.loadViewIfNeeded()
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let payment = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.payment" } as? UILabel)
        #expect(payment.text == "—")
        try await Task.sleep(for: .milliseconds(300))
        #expect(payment.text == "10.2 USDC")
        let liquidation = try #require(descendants(controller.view).first { $0.accessibilityIdentifier == "perps.leverage.liquidationPrice" } as? UILabel)
        #expect(liquidation.text == "$80")
    }

    private func order() -> PerpsOrderDisplayData {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH,
                                        input: .init(amount: "20", leverage: 2))
        data.editingPosition = .init(id: "wallet/btc", currentInput: .init(text: "20"), currentAmount: "$20", currentLeverage: 2)
        data.leverageOptions = [.init(value: 2), .init(value: 5)]
        data.canUseFractions = true
        return data
    }

    private func asset() throws -> ApiPerpsAsset {
        try JSONDecoder().decode(ApiPerpsAsset.self, from: Data("""
        {"id":"btc","name":"BTC","symbol":"BTC","chain":"hyperliquid","provider":"hyperliquid",
         "dex":"","szDecimals":4,"maxLeverage":40,"context":{"markPx":"100","prevDayPx":"100"}}
        """.utf8))
    }

    private func quote(payment: String) throws -> ApiPerpsQuote {
        try JSONDecoder().decode(ApiPerpsQuote.self, from: Data("""
        {"id":"review","accountId":"wallet","assetId":"btc","kind":"leverage","side":"long",
         "leverage":5,"previousLeverage":2,"inputAmount":"20","currentInputAmount":"20","collateral":"20",
         "previousCollateral":"20","size":"0.4","previousSize":"0.4","notional":"40","previousNotional":"40",
         "markPrice":"100","liquidationPrice":"50","estimatedLiquidationPrice":"80","paymentAmount":"\(payment)",
         "bridgeFee":"0","expiresAt":2000000000000,"createdAt":1900000000000}
        """.utf8))
    }

    private func position() throws -> ApiPerpsAccountPosition {
        try JSONDecoder().decode(ApiPerpsAccountPosition.self, from: Data("""
        {"id":"wallet/btc","assetId":"btc","dex":"","side":"long","size":"0.4","collateral":"20","equity":"20",
         "raw":{"coin":"BTC","entryPx":"100","liquidationPx":"50","leverage":{"type":"isolated","value":2},
         "marginUsed":"20","positionValue":"40","returnOnEquity":"0","szi":"0.4","unrealizedPnl":"0"}}
        """.utf8))
    }
}
