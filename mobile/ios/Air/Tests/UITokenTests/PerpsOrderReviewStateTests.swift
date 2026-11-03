import Foundation
import Testing
import WalletCore
@testable import UIToken

@Suite @MainActor
struct PerpsOrderReviewStateTests {
    private func fixture(status: PerpsOrderReviewDisplayData.Status = .ready) -> PerpsOrderReviewDisplayData {
        .init(token: .TONCOIN, direction: .short, leverage: 5, margin: .fromDouble(100.2, .USD),
              positionSize: "$501", price: "$5", liquidationPrice: "$6", paymentAmount: "100.2 USDT",
              fee: "$0.56", status: status)
    }

    @Test func `confirmation is tied to the displayed quote and cannot be sent twice`() throws {
        let data = fixture()
        var requests: [PerpsOrderReviewRequest] = []
        let state = PerpsOrderReviewState(data: data) { requests.append($0) }
        state.confirm()
        state.confirm()
        #expect(requests.count == 1)
        #expect(requests.first?.reviewID == data.id)
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

    @Test func `a refreshed quote is the one sent to the adapter`() {
        let initial = fixture(status: .loading)
        var requests: [PerpsOrderReviewRequest] = []
        let state = PerpsOrderReviewState(data: initial) { requests.append($0) }
        state.confirm()
        #expect(requests.isEmpty)
        let refreshed = fixture()
        #expect(state.update(data: refreshed))
        state.confirm()
        #expect(requests.first?.reviewID == refreshed.id)
    }

    @Test func `expired quotes stay visible but cannot be confirmed`() {
        let data = fixture()
        let state = PerpsOrderReviewState(data: data) { _ in Issue.record("Unexpected confirmation") }
        var expired = data
        expired.status = .unavailable("Quote expired")
        #expect(state.update(data: expired))
        state.confirm()
        #expect(!state.canConfirm)
        #expect(state.data.id == data.id)
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
        #expect(state.data.id == requote.id)
        #expect(state.canConfirm)
    }

    @Test func `position adjustments require identity and preserve the quoted operation`() throws {
        var data = fixture()
        data.mode = .increase(.init(margin: .fromDouble(75, .USD), positionSize: "$375", liquidationPrice: "$4"))
        var requests: [PerpsOrderReviewRequest] = []
        let state = PerpsOrderReviewState(data: data) { requests.append($0) }
        state.confirm()
        #expect(requests.isEmpty)
        data.positionID = "btc-position"
        let identified = PerpsOrderReviewState(data: data) { requests.append($0) }
        identified.confirm()
        let request = try #require(requests.first)
        #expect(request.operation == .increase)
        #expect(request.positionID == "btc-position")
        var wrongPosition = data
        wrongPosition.positionID = "another-position"
        #expect(!identified.update(data: wrongPosition, for: request))
        var wrongOperation = data
        wrongOperation.mode = .open
        #expect(!identified.update(data: wrongOperation, for: request))
        #expect(identified.update(data: data, for: request))
    }

    @Test func `receive token requotes serialize with confirmation and reject late replies`() throws {
        var data = fixture()
        data.positionID = "btc-position"
        data.mode = .close(.init(invested: "$100", currentValue: "$130", entryPrice: "$5"))
        data.canSelectPayment = true
        var selections: [PerpsOrderReviewRequest] = []
        var confirmations: [PerpsOrderReviewRequest] = []
        let state = PerpsOrderReviewState(data: data, onSelectPayment: { selections.append($0) }, onConfirm: { confirmations.append($0) })
        state.selectPayment()
        state.selectPayment()
        state.confirm()
        #expect(selections.count == 1)
        #expect(confirmations.isEmpty)
        let selection = try #require(selections.first)
        #expect(selection.action == .selectPayment)
        #expect(selection.operation == .close)
        data.paymentAmount = "130 USDT"
        #expect(state.update(data: data, for: selection))
        state.confirm()
        #expect(confirmations.count == 1)
        #expect(!state.update(data: data, for: selection))
        #expect(!state.canSelectPayment)
    }
}
