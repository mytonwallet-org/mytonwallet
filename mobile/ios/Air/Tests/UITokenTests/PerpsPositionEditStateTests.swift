import Testing
import UIComponents
import WalletCore
@testable import UIToken

@Suite @MainActor
struct PerpsPositionEditStateTests {
    private func fixture(change: PerpsOrderDisplayData.EditingPosition.Change? = nil,
                         id: String = "position-1") -> PerpsOrderDisplayData {
        var data = PerpsOrderDisplayData(token: .TONCOIN, direction: .long, paymentToken: .TON_USDT,
                                        input: .init(amount: change == nil ? "100.2" : "125.2", leverage: 10), maxLeverage: 10)
        data.editingPosition = .init(id: id, currentInput: .init(text: "100.2"), currentCollateral: "100.213", currentAmount: "$100.2",
                                     currentLeverage: 10, change: change, liquidationPrice: "$4.50")
        data.status = change == nil ? .idle : .ready
        data.positionSize = "$1 252"
        data.paymentAmount = "25"
        data.networkFee = "$0.01"
        return data
    }

    @Test(arguments: [PerpsOrderDisplayData.EditingPosition.Change.increase, .reduce])
    func `review uses adapter classification and includes position identity`(_ change: PerpsOrderDisplayData.EditingPosition.Change) {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: fixture(change: change)) { requests.append($0) }
        // Both cases deliberately use the same text: the UI cannot infer the operation from a number.
        #expect(state.data.editingPosition?.change == change)
        #expect(state.canReview)
        state.request(.review)
        state.request(.review)
        #expect(requests.count == 1)
        #expect(requests.first?.positionID == "position-1")
        #expect(requests.first?.input.amount.text == "125.2")
        #expect(!state.canReview)
    }

    @Test func `unchanged and unquoted amounts cannot be reviewed`() {
        var data = fixture()
        data.status = .ready
        let state = PerpsOrderState(data: data) { _ in Issue.record("Unexpected request") }
        #expect(!state.canReview)
        #expect(!state.hasPositionChanges)
        state.request(.review)
        state.request(.resetAmount)
        data.input.amount = .init(text: "150")
        #expect(state.update(data: data))
        #expect(state.hasPositionChanges)
        #expect(!state.canReview)
        state.request(.review)
    }

    @Test func `reset supersedes an edited quote and restores the supplied baseline`() throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: fixture(change: .increase)) { requests.append($0) }
        state.editAmount(.init(text: "75.2"))
        let edit = try #require(requests.last)
        #expect(state.data.editingPosition?.change == nil)
        #expect(state.data.editingPosition?.liquidationPrice == nil)
        #expect(state.data.networkFee == nil)
        #expect(state.data.paymentAmount == "25")
        #expect(state.data.editingPosition?.currentInput.text == "100.2")
        state.request(.resetAmount)
        let reset = try #require(requests.last)
        #expect(reset.action == .resetAmount)
        #expect(reset.input.amount.text == "100.2")
        #expect(reset.input.intent == .current)
        #expect(state.data.input.amount.text == "100.2")
        #expect(!state.update(data: fixture(change: .reduce), for: edit))
        #expect(state.update(data: fixture(), for: reset))
        #expect(state.data.input.amount.text == "100.2")
        #expect(!state.hasPositionChanges)
        #expect(!state.canReview)
    }

    @Test func `a matching request cannot change the position or switch to an opening order`() throws {
        var request: PerpsOrderRequest?
        let state = PerpsOrderState(data: fixture()) { request = $0 }
        state.editAmount(.init(text: "125.2"))
        let edit = try #require(request)
        #expect(!state.update(data: fixture(change: .increase, id: "position-2"), for: edit))
        var opening = fixture(change: .increase)
        opening.editingPosition = nil
        #expect(!state.update(data: opening, for: edit))
        #expect(state.update(data: fixture(change: .increase), for: edit))
        let openState = PerpsOrderState(data: opening) { _ in }
        #expect(!openState.update(data: fixture()))
    }

    @Test func `signed adjustments ask the SDK for a share of the current collateral at the current leverage`() {
        var data = fixture()
        data.input.amount = .init(text: "125.2")
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.request(.leverageChanged)
        state.request(.fraction(100))
        #expect(requests.isEmpty)
        for value in [-25, -5, 5, 25] { state.request(.fraction(value)) }
        #expect(requests.map(\.input.fraction) == [-25, -5, 5, 25])
        // The fill rounds the exact collateral changed by the percentage to cents.
        #expect(requests.map(\.input.amount.text) == ["75.16", "95.2", "105.22", "125.27"])
        #expect(requests.allSatisfy { $0.input.leverage == 10 && $0.positionID == "position-1" })
    }

    @Test func `a funding notice after an increase does not block a reduction request`() throws {
        var data = fixture(change: .increase)
        data.fundingRequirement = .init(title: "Not enough USDC", message: "Buy USDC on Arbitrum.",
            buttonTitle: "Not Enough USDC", actionTitle: "Buy USDC", action: .buyUsdc)
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        state.request(.review)
        state.request(.fraction(25))
        #expect(requests.isEmpty)
        state.request(.fraction(-25))
        let reduction = try #require(requests.last)
        #expect(reduction.input.fraction == -25)
        #expect(reduction.positionID == "position-1")
        #expect(!state.canReview)
        var response = fixture(change: .reduce)
        response.input.amount = .init(text: "75.15")
        #expect(state.update(data: response, for: reduction))
        #expect(state.data.fundingRequirement == nil)
        #expect(state.canReview)
    }

}
