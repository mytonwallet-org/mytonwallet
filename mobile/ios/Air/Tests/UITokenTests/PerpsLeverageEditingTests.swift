import Foundation
import Testing
import UIKit
import UIComponents
import WalletCore
import WalletResources
@testable import UIToken

@Suite @MainActor
struct PerpsLeverageEditingTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: ["20", "30"])
    func editingKeepsCurrentLeverageAfterSelectionAndReset(amount: String) throws {
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: makeOrder()) { requests.append($0) }
        state.editAmount(.init(text: amount))
        let requestCount = requests.count
        #expect(!state.canSelectLeverage)
        state.selectLeverage(5)
        state.request(.leverageChanged)
        #expect(requests.count == requestCount)
        #expect(state.data.input.leverage == 2)
        state.request(.resetAmount)
        #expect(!state.canSelectLeverage)
        state.selectLeverage(5)
        #expect(state.data.input.leverage == 2)
        #expect(!state.hasPositionChanges)
        let draft = PerpsSDKAdapter.draft(assetId: "btc", side: .long, input: state.data.input, isEditing: true)
        #expect(draft.leverage == 2)
        #expect(draft.leverageOnly != true)
    }

    @Test func openingStillSelectsLeverageWithinTheMarketLimit() throws {
        var data = makeOrder()
        data.editingPosition = nil
        var requests: [PerpsOrderRequest] = []
        let state = PerpsOrderState(data: data) { requests.append($0) }
        #expect(state.canSelectLeverage)
        state.selectLeverage(7)
        #expect(requests.isEmpty)
        state.selectLeverage(5)
        let request = try #require(requests.last)
        #expect(request.action == .leverageChanged)
        #expect(request.input.leverage == 5)
        #expect(request.positionID == nil)
    }

    @Test(arguments: [false, true])
    func editingFooterShowsLiquidationAndSizeWithoutLeverage(isEditing: Bool) throws {
        var data = makeOrder()
        if !isEditing { data.editingPosition = nil }
        let state = PerpsOrderState(data: data, onRequest: { _ in })
        let content = PerpsOrderView(state: state, selectLeverage: {})
        content.frame = CGRect(x: 0, y: 0, width: 402, height: 844)
        content.layoutIfNeeded()
        let views = collectDescendants(content)
        let leverage = try #require(views.first { $0.accessibilityIdentifier == "perps.order.leverage" })
        let liquidation = try #require(views.first { $0.accessibilityIdentifier == "perps.order.liquidationPrice" })
        let positionSize = try #require(views.first { $0.accessibilityIdentifier == "perps.order.positionSize" })
        #expect(try #require(leverage.superview?.superview as? TradePresenceView).showsContent != isEditing)
        #expect(try #require(liquidation.superview?.superview as? TradePresenceView).showsContent == isEditing)
        #expect(try #require(positionSize.superview?.superview as? TradePresenceView).showsContent)
        if isEditing {
            let liquidationFrame = liquidation.convert(liquidation.bounds, to: content.amountCard)
            let sizeFrame = positionSize.convert(positionSize.bounds, to: content.amountCard)
            #expect(liquidationFrame.minY == sizeFrame.minY)
            #expect(liquidationFrame.maxX < sizeFrame.minX)
        }
    }

    private func collectDescendants(_ view: UIView) -> [UIView] {
        view.subviews.flatMap { [$0] + collectDescendants($0) }
    }

    private func makeOrder() -> PerpsOrderDisplayData {
        var data = PerpsOrderDisplayData(token: .ETH, direction: .long, paymentToken: .ETH,
                                        input: .init(amount: "20", leverage: 2), maxLeverage: 5)
        data.editingPosition = .init(id: "wallet/btc", currentInput: .init(text: "20"), currentCollateral: "20",
                                     currentAmount: "$20", currentLeverage: 2, liquidationPrice: "$50")
        data.positionSize = "$40"
        return data
    }
}
