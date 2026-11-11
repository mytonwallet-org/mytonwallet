import Foundation
import Perception
import UIComponents
import WalletCore
import WalletContext

/// Owns local editing and response ordering. The caller owns order and quote semantics.
@Perceptible @MainActor
final class PerpsOrderState {
    private(set) var data: PerpsOrderDisplayData
    private(set) var latestRequestID: UUID?
    private var latestRequestAction: PerpsOrderRequest.Action?
    private var estimateRefreshActive = false
    private var estimateRefreshGeneration = UUID()
    @PerceptionIgnored private let onRequest: (PerpsOrderRequest) -> Void

    init(data: PerpsOrderDisplayData, onRequest: @escaping (PerpsOrderRequest) -> Void) {
        self.data = data
        self.onRequest = onRequest
    }

    var canReview: Bool {
        guard data.status == .ready, data.input.hasAmount, data.fundingRequirement == nil else { return false }
        return data.editingPosition.map { $0.change != nil } ?? true
    }

    var hasPositionChanges: Bool {
        guard let position = data.editingPosition else { return false }
        return data.input.amount != position.currentInput
    }

    var canSelectLeverage: Bool {
        data.editingPosition == nil && data.fundingRequirement == nil
    }

    var canRetryFunding: Bool {
        guard case .unavailable = data.status else { return false }
        return latestRequestAction == .refreshFunding
    }

    var fractionPresets: [Int] {
        data.editingPosition == nil ? [25, 50, 100] : [-25, -5, 5, 25]
    }

    struct EstimateRefreshRequest: Equatable, Sendable {
        var generation: UUID
        var requestID: UUID?
        var amount: String
        var leverage: Int
        var intent: PerpsOrderInput.Intent
        var funding: ApiPerpsFundingSource
        var positionID: String?

        var input: PerpsOrderInput {
            .init(amount: amount, leverage: leverage, intent: intent, funding: funding)
        }
    }

    var estimateRefreshRequest: EstimateRefreshRequest? {
        guard estimateRefreshActive, data.input.hasAmount, data.fundingRequirement == nil,
              data.status == .ready || data.status == .idle else { return nil }
        return .init(generation: estimateRefreshGeneration, requestID: latestRequestID, amount: data.input.amount.text,
                     leverage: data.input.leverage, intent: data.input.intent, funding: data.input.funding,
                     positionID: data.editingPosition?.id)
    }

    func setEstimateRefreshActive(_ active: Bool) {
        guard estimateRefreshActive != active else { return }
        estimateRefreshActive = active
        estimateRefreshGeneration = UUID()
    }

    @discardableResult
    func applyEstimateRefresh(_ data: PerpsOrderDisplayData, for request: EstimateRefreshRequest) -> Bool {
        guard estimateRefreshRequest == request, data.editingPosition?.id == request.positionID else { return false }
        replace(with: data, keepingInput: true)
        return true
    }

    @discardableResult
    func update(data: PerpsOrderDisplayData, for request: PerpsOrderRequest? = nil) -> Bool {
        guard latestRequestID == request?.id,
              data.editingPosition?.id == self.data.editingPosition?.id else { return false }
        replace(with: data, keepingInput: false)
        return true
    }

    /// The opening maximum stays known between quotes that do not report it.
    private func replace(with data: PerpsOrderDisplayData, keepingInput: Bool) {
        var updated = data
        if keepingInput { updated.input = self.data.input }
        updated.availableCollateral = data.availableCollateral ?? self.data.availableCollateral
        self.data = updated
    }

    func editAmount(_ input: TradeAmountInput) {
        guard data.input.amount != input else { return }
        resetLeverageToCurrent()
        data.input.amount = input
        data.input.intent = input == data.editingPosition?.currentInput ? .current : .amount
        request(.amountChanged)
    }

    func selectLeverage(_ value: Int) {
        guard canSelectLeverage, data.leverageRange.contains(value), value != data.input.leverage else { return }
        data.input.leverage = value
        request(.leverageChanged)
    }

    var canSelectFunding: Bool {
        (data.hyperliquidBalance != nil || data.input.funding == .balance) && data.editingPosition?.change != .reduce
    }

    /// The opening maximum depends on the source, so percentages wait for its quote; a filled share stays as typed text.
    func selectFunding(_ funding: ApiPerpsFundingSource) {
        guard funding != data.input.funding, funding == .wallet || canSelectFunding else { return }
        data.input.funding = funding
        if data.input.fraction != nil { data.input.intent = .amount }
        data.availableCollateral = nil
        request(.fundingChanged)
    }

    private func resetLeverageToCurrent() {
        if let leverage = data.editingPosition?.currentLeverage { data.input.leverage = leverage }
    }

    func request(_ action: PerpsOrderRequest.Action) {
        switch action {
        case .review: guard canReview else { return }
        case .fraction(let percentage):
            guard data.canUseFractions, fractionPresets.contains(percentage),
                  data.fundingRequirement == nil || (data.editingPosition != nil && percentage < 0) else { return }
            resetLeverageToCurrent()
            // Fills at once; the quote for the exact share follows.
            if let amount = data.amount(forFraction: percentage) { data.input.amount = amount }
            data.input.intent = .fraction(percentage)
        case .resetAmount:
            guard hasPositionChanges else { return }
            resetLeverageToCurrent()
            if let position = data.editingPosition { data.input.amount = position.currentInput }
            data.input.intent = .current
        case .leverageChanged: guard canSelectLeverage else { return }
        case .buyUsdc, .buyEth:
            let expectedAction: PerpsOrderDisplayData.FundingAction = action == .buyUsdc ? .buyUsdc : .buyEth
            guard data.fundingRequirement?.action == expectedAction else { return }
            onRequest(PerpsOrderRequest(id: UUID(), action: action, input: data.input, positionID: data.editingPosition?.id))
            return
        default: break
        }
        let request = PerpsOrderRequest(id: UUID(), action: action, input: data.input, positionID: data.editingPosition?.id)
        latestRequestID = request.id
        latestRequestAction = action
        data.status = data.editingPosition == nil && !data.input.hasAmount
            && (action == .amountChanged || action == .leverageChanged) ? .idle : .loading
        if action != .review && action != .refreshFunding {
            if action == .leverageChanged {
                data.paymentAmount = nil
            }
            if !data.input.hasAmount {
                data.conversion = nil
                data.paymentAmount = nil
            }
            data.positionSize = nil
            data.bridgeFee = nil
            data.tradingFee = nil
            data.networkFee = nil
            data.leverageEstimate = nil
            data.editingPosition?.change = nil
            data.editingPosition?.liquidationPrice = nil
        }
        onRequest(request)
    }
}
