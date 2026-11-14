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
        case balanceWithdrawal(PerpsBalanceWithdrawalReviewDisplayData)

        public var title: String {
            switch self {
            case .opened: lang("Position Opened")
            case .leverageChanged: lang("Leverage")
            case .increased: lang("Position Increased")
            case .reduced: lang("Position Reduced")
            case .closed: lang("Position Closed")
            case .liquidated: lang("Position Liquidated")
            case .balanceWithdrawal: lang("PerpsWithdrawalCompleted")
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
        var isBalanceWithdrawal: Bool { if case .balanceWithdrawal = self { true } else { false } }
        var showsPlus: Bool { if case .closed = self { true } else { false } }
    }

    public var status: Status = .completed
    public var isEstimated = false
    public var title: String {
        switch status {
        case .pending: lang("In Progress")
        case .attention: lang(event.isBalanceWithdrawal ? "PerpsWithdrawalStatus" : "PerpsOperationStatus")
        case .failed: lang("Failed")
        case .submitted, .completed: event.title
        }
    }
    var canShare: Bool { status == .submitted || status == .completed }
    /// `.completed` means Hyperliquid accepted the withdrawal, and the USDC is still bridging to the wallet
    var balanceWithdrawalNote: String? {
        switch status {
        case .pending: lang("PerpsWithdrawalProcessing")
        case .submitted, .completed: lang("PerpsWithdrawalOnItsWay")
        case .attention, .failed: nil
        }
    }
    public var event: Event
    public let token: ApiToken
    public let direction: PerpsTradeDirection
    public var leverage: Int
    public var margin: BaseCurrencyAmount
    public var summaryTradeSize: BaseCurrencyAmount?
    var summaryAmount: BaseCurrencyAmount { summaryTradeSize ?? margin }
    var expandedSummaryAmount: BaseCurrencyAmount { receivedAmount ?? summaryAmount }
    var expandedSummaryIsEstimated: Bool { receivedAmount == nil && isEstimated }
    var summaryPreviousMargin: BaseCurrencyAmount? { summaryTradeSize == nil ? event.previous?.margin : nil }
    var summaryTitle: String? {
        guard summaryAmount.optionalAmount != nil else { return nil }
        if event.outcome != nil { return lang("Profit and Loss") }
        return summaryTradeSize == nil ? nil : lang("Trade Size")
    }
    var expandedSummaryTitle: String? { receivedAmount == nil ? summaryTitle : lang("You Received") }
    private var receivedAmount: BaseCurrencyAmount? {
        guard case .closed(let outcome) = event, let amount = outcome.closingValueAmount,
              amount.optionalAmount != nil else { return nil }
        return amount
    }
    /// Milliseconds since the Unix epoch, matching activity receipt timestamps.
    public let timestamp: Int64
    public var positionSize: String
    public var isTradeSize = false
    public var positionSizeTitle: String { lang(isTradeSize ? "Trade Size" : "Position Size") }
    public let price: String
    public var liquidationPrice: String?
    public var paymentAmount: String
    public let fee: String
    public var feeRows: [PerpsFeeRow] = []
    public var feesAreEstimated = false
    public var remainingCollateral: String?
    public let transferID: String?

    var availableFeeRows: [PerpsFeeRow] { feeRows.filter { Self.isKnownValue($0.value) } }

    var outcomeSections: [[AssetInfoField]] {
        guard let outcome = event.outcome else { return [] }
        let profitLoss = outcome.profitLoss
        let result = event.isLiquidated
            ? AssetInfoField(id: "closingValue", title: lang("Closing Value"), info: lang("$perps_closing_value_hint"), value: outcome.closingValue)
            : AssetInfoField(id: "profitLoss", title: lang(profitLoss.tone == .negative ? "Loss" : "Profit"),
                             info: lang(profitLoss.tone == .negative ? "$perps_loss_hint" : "$perps_profit_hint"), value: profitLoss.text)
        var prices: [AssetInfoField] = []
        if Self.isKnownValue(outcome.entryPrice), Self.isKnownValue(outcome.exitPrice) {
            prices.append(.init(id: "prices", title: lang(event.isLiquidated ? "Entry / Liquidation Price" : "Entry / Exit Price"),
                                value: outcome.entryPrice + " / " + outcome.exitPrice))
        }
        let sections: [[AssetInfoField]] = [
            [.init(id: "invested", title: lang("Invested"), info: lang("$perps_invested_hint"), value: outcome.invested), result],
            [.init(id: "size", title: positionSizeTitle, info: isTradeSize ? nil : lang("$perps_position_size_details_hint"), value: positionSize)] + prices,
            [.init(id: "received", title: lang("You Received"), value: paymentAmount)]
                + (availableFeeRows.isEmpty ? [.init(id: "fee", title: lang("Fees"), info: lang("$perps_fees_hint"), value: fee)] : []),
        ]
        return sections.map { $0.filter { Self.isKnownValue($0.value) } }.filter { !$0.isEmpty }
    }

    private static func isKnownValue(_ value: String) -> Bool { !value.isEmpty && value != "—" }

    public init(token: ApiToken, direction: PerpsTradeDirection, leverage: Int, margin: BaseCurrencyAmount,
                timestamp: Int64, positionSize: String, price: String, liquidationPrice: String?,
                paymentAmount: String, fee: String, transferID: String? = nil,
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
        self.transferID = transferID
    }

    /// A withdrawal has no position, so the receipt reads only the event and leaves the position fields empty.
    public init(balanceWithdrawal: PerpsBalanceWithdrawalReviewDisplayData, timestamp: Int64) {
        self.init(token: balanceWithdrawal.token, direction: .long, leverage: 0, margin: PerpsFormatting.usd(nil),
                  timestamp: timestamp, positionSize: "", price: "", liquidationPrice: nil,
                  paymentAmount: balanceWithdrawal.formattedReceiveAmount, fee: "", event: .balanceWithdrawal(balanceWithdrawal))
    }
}
