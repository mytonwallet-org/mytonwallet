import Foundation
import Testing
import WalletCore
@testable import UIToken

@Suite @MainActor
struct PerpsOrderReviewStateTests {
    private func fixture(status: PerpsOrderReviewDisplayData.Status = .ready) -> PerpsOrderReviewDisplayData {
        var data = PerpsOrderReviewDisplayData(token: .TONCOIN, direction: .short, leverage: 5, margin: .fromDouble(100.2, .USD),
              positionSize: "$501", price: "$5", liquidationPrice: "$6", paymentAmount: "100.2 USDT",
              fee: "$0.56", paymentToken: .TON_USDT)
        data.status = status
        return data
    }

    @Test func `confirmation cannot be sent twice before the adapter answers it`() throws {
        let data = fixture()
        var requests: [PerpsOrderReviewRequest] = []
        let state = PerpsOrderReviewState(data: data) { requests.append($0) }
        state.confirm()
        state.confirm()
        #expect(requests.count == 1)
        #expect(state.data.status == .loading)
        #expect(!state.canConfirm)
        #expect(!state.update(data: data))
        let first = try #require(requests.first)
        #expect(state.update(data: data, for: first))
        state.confirm()
        #expect(requests.count == 2)
        #expect(!state.update(data: data, for: first))
        #expect(!state.canConfirm)
    }

    @Test func `a quote can be confirmed only once it is ready`() {
        var requests: [PerpsOrderReviewRequest] = []
        let state = PerpsOrderReviewState(data: fixture(status: .loading)) { requests.append($0) }
        state.confirm()
        #expect(requests.isEmpty)
        #expect(state.update(data: fixture()))
        state.confirm()
        #expect(requests.count == 1)
    }

    @Test func `expired quotes stay visible but cannot be confirmed`() {
        let data = fixture()
        let state = PerpsOrderReviewState(data: data) { _ in Issue.record("Unexpected confirmation") }
        var expired = data
        expired.status = .unavailable("Quote expired")
        #expect(state.update(data: expired))
        state.confirm()
        #expect(!state.canConfirm)
        #expect(state.data.margin == data.margin)
        #expect(state.data.paymentAmount == data.paymentAmount)
    }

    @Test func `requotes reject late updates from the previously confirmed quote`() throws {
        var request: PerpsOrderReviewRequest?
        let state = PerpsOrderReviewState(data: fixture()) { request = $0 }
        state.confirm()
        let previous = try #require(request)
        let requote = fixture()
        #expect(state.update(data: requote, for: previous))
        #expect(!state.update(data: fixture(status: .loading), for: previous))
        #expect(state.data.status == requote.status)
        #expect(state.canConfirm)
    }
}
