import Foundation
import WalletCore
import WalletContext

/// An adapter-owned quote, already priced and validated for review. No order is built by the view.
public struct PerpsOrderReviewDisplayData {
    public enum Operation: String, Sendable { case open, increase, reduce, close, leverage }
    public enum Mode {
        case open
        case increase(PerpsPositionChange)
        case reduce(PerpsPositionChange)
        case close(PerpsPositionClosing)
        case leverage(PerpsPositionChange)

        public var operation: Operation {
            switch self {
            case .open: .open
            case .increase: .increase
            case .reduce: .reduce
            case .close: .close
            case .leverage: .leverage
            }
        }

        var previous: PerpsPositionChange? {
            switch self {
            case .increase(let values), .reduce(let values), .leverage(let values): values
            default: nil
            }
        }

        var title: String {
            switch self {
            case .open: lang("Open Position")
            case .increase: lang("Increase Position")
            case .reduce: lang("Reduce Position")
            case .close: lang("Close Position")
            case .leverage: lang("PerpsChangeLeverage")
            }
        }
    }
    public enum Status: Equatable {
        case ready
        case loading
        case unavailable(String)
    }

    /// Use a new identity whenever the order or quote changes. Confirm returns this identity.
    public let id: UUID
    public var mode: Mode = .open
    public var positionID: String?
    public var token: ApiToken
    public var direction: PerpsTradeDirection
    public var leverage: Int
    public var margin: BaseCurrencyAmount
    public var isEstimated = false
    public var positionSize: String
    public var price: String
    public var liquidationPrice: String?
    public var paymentAmount: String
    public var fee: String
    public var feeExplanation: String?
    public var feeRows: [PerpsFeeRow] = []
    public var remainingCollateral: String?
    public var status: Status
    public var notice: String?
    public var paymentToken: ApiToken?
    public var paymentQuantity: String?
    public var canSelectPayment = false

    public init(id: UUID = UUID(), token: ApiToken, direction: PerpsTradeDirection, leverage: Int,
                margin: BaseCurrencyAmount, positionSize: String, price: String, liquidationPrice: String?,
                paymentAmount: String, fee: String, status: Status = .ready) {
        self.id = id
        self.token = token
        self.direction = direction
        self.leverage = leverage
        self.margin = margin
        self.positionSize = positionSize
        self.price = price
        self.liquidationPrice = liquidationPrice
        self.paymentAmount = paymentAmount
        self.fee = fee
        self.status = status
    }
}

public struct PerpsFeeRow: Identifiable {
    public var id: String
    public var title: String
    public var value: String
}

public struct PerpsOrderReviewRequest {
    public enum Action: Sendable { case confirm, selectPayment }
    public let id: UUID
    public let reviewID: UUID
    public let positionID: String?
    public let operation: PerpsOrderReviewDisplayData.Operation
    public let action: Action
}
