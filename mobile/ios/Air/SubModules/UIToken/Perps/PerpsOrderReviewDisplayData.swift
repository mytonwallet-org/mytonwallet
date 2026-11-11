import Foundation
import WalletCore
import WalletContext

/// An adapter-owned quote, already priced and validated for review. No order is built by the view.
public struct PerpsOrderReviewDisplayData {
    public enum Operation: String, Sendable { case open, increase, reduce, close }
    public enum Mode {
        case open
        case increase(PerpsPositionChange)
        case reduce(PerpsPositionChange)
        case close(PerpsPositionClosing)

        public var operation: Operation {
            switch self {
            case .open: .open
            case .increase: .increase
            case .reduce: .reduce
            case .close: .close
            }
        }

        var previous: PerpsPositionChange? {
            switch self {
            case .increase(let values), .reduce(let values): values
            default: nil
            }
        }

        var title: String {
            switch self {
            case .open: lang("Open Position")
            case .increase: lang("Increase Position")
            case .reduce: lang("Reduce Position")
            case .close: lang("Close Position")
            }
        }
    }
    public enum Status: Equatable {
        case ready
        case loading
        case unavailable(String)
    }

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
    /// Estimated total fee; nil while the venue reports fees only at execution.
    public var fee: String?
    public var feeRows: [PerpsFeeRow] = []
    public var remainingCollateral: String?
    public var status: Status = .ready
    public var notice: String?
    /// Set when the order also changes the whole Hyperliquid account.
    public var accountNotice: String?
    public var paymentToken: ApiToken

    public init(token: ApiToken, direction: PerpsTradeDirection, leverage: Int,
                margin: BaseCurrencyAmount, positionSize: String, price: String, liquidationPrice: String?,
                paymentAmount: String, fee: String?, paymentToken: ApiToken) {
        self.token = token
        self.direction = direction
        self.leverage = leverage
        self.margin = margin
        self.positionSize = positionSize
        self.price = price
        self.liquidationPrice = liquidationPrice
        self.paymentAmount = paymentAmount
        self.fee = fee
        self.paymentToken = paymentToken
    }
}

public struct PerpsFeeRow: Identifiable {
    public var id: String
    public var title: String
    public var value: String
}

/// Identifies one confirmation; an update for an older one is ignored.
public struct PerpsOrderReviewRequest {
    public let id: UUID
}
