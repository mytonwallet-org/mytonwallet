import Foundation
import Perception
import UIComponents
import WalletContext

/// Owns only local editing and response ordering. The caller owns order/quote semantics.
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
        if let position = data.editingPosition { return position.change != nil }
        return data.leverageOptions.contains { $0.value == data.input.leverage }
    }

    var hasPositionChanges: Bool {
        guard let position = data.editingPosition else { return false }
        return data.input.amount != position.currentInput || isChangingLeverage
    }

    var isChangingLeverage: Bool {
        data.editingPosition != nil && data.input.leverageOnly
    }

    var canSelectLeverage: Bool {
        guard data.fundingRequirement == nil, !data.leverageOptions.isEmpty else { return false }
        guard let position = data.editingPosition else { return true }
        return position.currentLeverage != nil && (data.input.amount == position.currentInput || isChangingLeverage)
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
        var leverageOnly: Bool
        var positionID: String?

        var input: PerpsOrderInput { .init(amount: amount, leverage: leverage, leverageOnly: leverageOnly) }
    }

    var estimateRefreshRequest: EstimateRefreshRequest? {
        guard estimateRefreshActive, data.input.hasAmount, data.fundingRequirement == nil,
              data.status == .ready || data.status == .idle else { return nil }
        return .init(generation: estimateRefreshGeneration, requestID: latestRequestID, amount: data.input.amount.text,
                     leverage: data.input.leverage, leverageOnly: data.input.leverageOnly, positionID: data.editingPosition?.id)
    }

    func setEstimateRefreshActive(_ active: Bool) {
        guard estimateRefreshActive != active else { return }
        estimateRefreshActive = active
        estimateRefreshGeneration = UUID()
    }

    @discardableResult
    func applyEstimateRefresh(_ data: PerpsOrderDisplayData, for request: EstimateRefreshRequest) -> Bool {
        guard estimateRefreshRequest == request, data.editingPosition?.id == request.positionID else { return false }
        var updated = data
        updated.input = self.data.input
        updated.availableCollateral = data.availableCollateral ?? self.data.availableCollateral
        updated.canUseFractions = data.editingPosition != nil || updated.availableCollateral != nil
        self.data = updated
        return true
    }

    @discardableResult
    func update(data: PerpsOrderDisplayData, for request: PerpsOrderRequest? = nil) -> Bool {
        guard latestRequestID == request?.id,
              data.editingPosition?.id == self.data.editingPosition?.id else { return false }
        self.data = data
        return true
    }

    func editAmount(_ input: TradeAmountInput) {
        guard data.input.amount != input else { return }
        if isChangingLeverage {
            data.paymentAmount = nil
        }
        if let leverage = data.editingPosition?.currentLeverage { data.input.leverage = leverage }
        data.input.leverageOnly = false
        data.input.amount = input
        request(.amountChanged)
    }

    func selectLeverage(_ value: Int) {
        guard canSelectLeverage,
              data.leverageOptions.contains(where: { $0.value == value }), value != data.input.leverage else { return }
        if let position = data.editingPosition { data.input.amount = position.currentInput }
        data.input.leverage = value
        data.input.leverageOnly = data.editingPosition.map { $0.currentLeverage != value } ?? false
        request(.leverageChanged)
    }

    func request(_ action: PerpsOrderRequest.Action) {
        switch action {
        case .review: guard canReview else { return }
        case .fraction(let percentage):
            guard data.canUseFractions, fractionPresets.contains(percentage),
                  data.fundingRequirement == nil || (data.editingPosition != nil && percentage < 0),
                  let basis = data.editingPosition?.currentInput ?? data.availableCollateral else { return }
            let factor = data.editingPosition == nil ? percentage : 100 + percentage
            var input = TradeAmountInput()
            input.set(basis.amount(decimals: data.currencyDecimals) * BigInt(factor) / 100, decimals: data.currencyDecimals)
            editAmount(input)
            return
        case .resetAmount:
            guard hasPositionChanges else { return }
            if let leverage = data.editingPosition?.currentLeverage { data.input.leverage = leverage }
            data.input.leverageOnly = false
        case .leverageChanged: guard canSelectLeverage else { return }
        case .selectPayment: guard data.canSelectPayment else { return }
        case .selectAccount: guard data.canSelectAccount else { return }
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
            if action == .leverageChanged || data.editingPosition?.change == .leverage {
                data.paymentAmount = nil
            }
            if !data.input.hasAmount {
                data.conversion = nil
                data.paymentAmount = nil
            }
            data.positionSize = nil
            data.swapFee = nil
            data.tradingFee = nil
            data.networkFee = nil
            data.editingPosition?.change = nil
            data.editingPosition?.liquidationPrice = nil
            // Estimates are tied to the previous draft. Keep supported values, clear derived details.
            data.leverageOptions = data.leverageOptions.map {
                .init(value: $0.value, isPreset: $0.isPreset)
            }
        }
        onRequest(request)
    }
}
