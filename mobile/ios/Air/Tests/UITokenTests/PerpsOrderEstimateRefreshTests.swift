import Foundation
import Testing
import UIComponents
import WalletCore
@testable import UIToken

@Suite @MainActor
struct PerpsOrderEstimateRefreshTests {
    @Test func refreshKeepsAmountsAndReviewAvailableWithoutLoading() throws {
        let state = PerpsOrderState(data: order()) { _ in }
        #expect(state.estimateRefreshRequest == nil)
        state.setEstimateRefreshActive(true)
        let refresh = try #require(state.estimateRefreshRequest)
        #expect(state.canReview)
        #expect(state.data.status == .ready)
        var update = order()
        update.input.amount = .init(text: "20")
        update.conversion = "0.005 BTC"
        update.availableCollateral = nil
        #expect(state.applyEstimateRefresh(update, for: refresh))
        #expect(state.data.input.amount.text == "20.00")
        #expect(state.data.conversion == "0.005 BTC")
        #expect(state.data.availableCollateral?.text == "100")
        #expect(state.canReview)
        #expect(state.data.status == .ready)
        #expect(state.latestRequestID == nil)
    }

    @Test func typingInvalidatesARefreshEvenWhenTheSameAmountIsRestored() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: order()) { requests.append($0) }
        state.setEstimateRefreshActive(true)
        let stale = try #require(state.estimateRefreshRequest)
        state.editAmount(.init(text: "25"))
        #expect(state.estimateRefreshRequest == nil)
        #expect(!state.applyEstimateRefresh(order(), for: stale))
        state.editAmount(.init(text: "20.00"))
        let latest = try #require(requests.last)
        #expect(state.update(data: order(), for: latest))
        #expect(state.estimateRefreshRequest != nil)
        #expect(!state.applyEstimateRefresh(order(), for: stale))
    }

    @Test func reviewAndCoveredControllersDoNotAcceptBackgroundEstimates() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: order()) { requests.append($0) }
        state.setEstimateRefreshActive(true)
        let stale = try #require(state.estimateRefreshRequest)
        state.request(.review)
        let review = try #require(requests.last)
        #expect(state.estimateRefreshRequest == nil)
        #expect(!state.applyEstimateRefresh(order(), for: stale))
        #expect(state.update(data: order(), for: review))
        state.setEstimateRefreshActive(false)
        #expect(state.estimateRefreshRequest == nil)
        #expect(!state.applyEstimateRefresh(order(), for: stale))
        #expect(state.canReview)
        state.setEstimateRefreshActive(true)
        #expect(state.estimateRefreshRequest != nil)
        #expect(!state.applyEstimateRefresh(order(), for: stale))
    }

    @Test func hidingOrBackgroundingInvalidatesThePreviousVisibilitySession() throws {
        let state = PerpsOrderState(data: order()) { _ in }
        state.setEstimateRefreshActive(true)
        let stale = try #require(state.estimateRefreshRequest)
        state.setEstimateRefreshActive(false)
        #expect(state.estimateRefreshRequest == nil)
        #expect(!state.applyEstimateRefresh(order(), for: stale))
        state.setEstimateRefreshActive(true)
        let resumed = try #require(state.estimateRefreshRequest)
        #expect(stale != resumed)
        #expect(!state.applyEstimateRefresh(order(), for: stale))
        #expect(state.applyEstimateRefresh(order(), for: resumed))
    }

    @Test func fundingNoticesSuspendRefreshAndRemainWhileTheInputChanges() throws {
        var data = order()
        data.fundingRequirement = .init(title: "Not enough USDC", message: "Buy USDC", buttonTitle: "Not enough USDC",
                                        actionTitle: "Buy USDC", action: .buyUsdc)
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.setEstimateRefreshActive(true)
        #expect(state.estimateRefreshRequest == nil)
        state.editAmount(.init(text: "15"))
        #expect(state.data.fundingRequirement == data.fundingRequirement)
        #expect(state.estimateRefreshRequest == nil)
        #expect(!state.canReview)
        let request = try #require(requests.last)
        var funded = order()
        funded.input = request.input
        #expect(state.update(data: funded, for: request))
        #expect(state.data.fundingRequirement == nil)
        #expect(state.estimateRefreshRequest != nil)
    }

    @Test func leverageFundingNoticeSurvivesSwitchingBackToAnAmountEdit() {
        var data = order()
        data.editingPosition = .init(id: "btc", currentInput: .init(text: "20.00"), currentAmount: "$20",
                                     change: .leverage, currentLeverage: 2)
        data.input.leverage = 5
        data.input.leverageOnly = true
        data.fundingRequirement = .init(title: "Not enough USDC", message: "Buy USDC", buttonTitle: "Not enough USDC",
                                        actionTitle: "Buy USDC", action: .buyUsdc)
        let state = PerpsOrderState(data: data) { request in
            #expect(!request.input.leverageOnly)
            #expect(request.input.leverage == 2)
        }
        state.editAmount(.init(text: "15"))
        #expect(state.data.fundingRequirement == data.fundingRequirement)
        #expect(state.data.paymentAmount == nil)
        #expect(!state.canReview)
    }

    private func order() -> PerpsOrderDisplayData {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH,
                                        input: .init(amount: "20.00", leverage: 2))
        data.status = .ready
        data.leverageOptions = [.init(value: 2), .init(value: 5)]
        data.availableCollateral = .init(text: "100")
        data.canUseFractions = true
        data.paymentAmount = "20.2"
        return data
    }
}
