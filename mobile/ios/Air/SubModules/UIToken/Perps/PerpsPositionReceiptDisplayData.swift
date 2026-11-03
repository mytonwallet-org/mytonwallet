import Foundation
import WalletCore
import WalletContext

public struct PerpsPositionOutcome {
    public let invested: String
    public let closingValue: String
    public let closingValueAmount: BaseCurrencyAmount?
    public let entryPrice: String
    public let exitPrice: String
    public let profitLoss: PerpsPositionDisplayData.Value
    public let heldDuration: String?

    public init(invested: String, closingValue: String, entryPrice: String, exitPrice: String,
                profitLoss: PerpsPositionDisplayData.Value, heldDuration: String? = nil, closingValueAmount: BaseCurrencyAmount? = nil) {
        self.invested = invested
        self.closingValue = closingValue
        self.closingValueAmount = closingValueAmount
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.profitLoss = profitLoss
        self.heldDuration = heldDuration
    }
}

/// Receipt presentation keeps submitted trades optimistic without changing their execution state.
public struct PerpsPositionReceiptDisplayData {
    public enum Status: Equatable {
        case pending
        case submitted
        case completed
        case attention(String)
        case failed(String)

        var message: String? {
            switch self {
            case .attention(let message), .failed(let message): message
            default: nil
            }
        }
    }

    public enum Event {
        case opened
        case leverageChanged
        case increased(PerpsPositionChange)
        case reduced(PerpsPositionChange, profitLoss: PerpsPositionDisplayData.Value, entryPrice: String)
        case closed(PerpsPositionOutcome)
        case liquidated(PerpsPositionOutcome)

        public var title: String {
            switch self {
            case .opened: lang("Position Opened")
            case .leverageChanged: lang("Leverage")
            case .increased: lang("Position Increased")
            case .reduced: lang("Position Reduced")
            case .closed: lang("Position Closed")
            case .liquidated: lang("Position Liquidated")
            }
        }
        var previous: PerpsPositionChange? {
            switch self {
            case .increased(let previous), .reduced(let previous, _, _): previous
            default: nil
            }
        }
        var outcome: PerpsPositionOutcome? {
            switch self {
            case .closed(let outcome), .liquidated(let outcome): outcome
            default: nil
            }
        }
        var isLiquidated: Bool { if case .liquidated = self { true } else { false } }
        var showsPlus: Bool { if case .closed = self { true } else { false } }
    }

    public var status: Status = .completed
    public var isEstimated = false
    public var title: String {
        switch status {
        case .pending: lang("In Progress")
        case .attention: lang("PerpsOperationStatus")
        case .failed: lang("Failed")
        case .submitted, .completed: event.title
        }
    }
    var canShare: Bool { status == .submitted || status == .completed }
    public var event: Event
    public let token: ApiToken
    public let direction: PerpsTradeDirection
    public var leverage: Int
    public var margin: BaseCurrencyAmount
    public var summaryTradeSize: BaseCurrencyAmount?
    var summaryAmount: BaseCurrencyAmount { summaryTradeSize ?? margin }
    var expandedSummaryAmount: BaseCurrencyAmount {
        if case .closed(let outcome) = event {
            return outcome.closingValueAmount ?? PerpsFormatting.usd(nil)
        }
        return summaryAmount
    }
    var expandedSummaryIsEstimated: Bool {
        if case .closed = event { return false }
        return isEstimated
    }
    var summaryPreviousMargin: BaseCurrencyAmount? { summaryTradeSize == nil ? event.previous?.margin : nil }
    var summaryTitle: String? { summaryTradeSize == nil ? nil : lang("Trade Size") }
    /// Milliseconds since the Unix epoch, matching activity receipt timestamps.
    public let timestamp: Int64
    public var positionSize: String
    public var isTradeSize = false
    public var positionSizeTitle: String { lang(isTradeSize ? "Trade Size" : "Position Size") }
    public let price: String
    public var liquidationPrice: String?
    public var paymentAmount: String
    public let fee: String
    public let feeExplanation: String?
    public var feeRows: [PerpsFeeRow] = []
    public var feesAreEstimated = false
    public var remainingCollateral: String?
    public let transferID: String?

    public init(token: ApiToken, direction: PerpsTradeDirection, leverage: Int, margin: BaseCurrencyAmount,
                timestamp: Int64, positionSize: String, price: String, liquidationPrice: String?,
                paymentAmount: String, fee: String, feeExplanation: String? = nil, transferID: String? = nil,
                event: Event = .opened) {
        self.event = event
        self.token = token
        self.direction = direction
        self.leverage = leverage
        self.margin = margin
        self.timestamp = timestamp
        self.positionSize = positionSize
        self.price = price
        self.liquidationPrice = liquidationPrice
        self.paymentAmount = paymentAmount
        self.fee = fee
        self.feeExplanation = feeExplanation
        self.transferID = transferID
    }
}
