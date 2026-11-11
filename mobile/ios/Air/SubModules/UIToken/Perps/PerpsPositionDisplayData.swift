import UIComponents
import WalletCore
import WalletContext

/// A caller-owned position snapshot. Equity, P&L, funding, and history are never calculated by the UI.
public struct PerpsPositionDisplayData {
    public var id: String
    public var market: PerpsMarketDisplayData
    public var direction: PerpsTradeDirection
    public var leverage: Int
    public var equity: BaseCurrencyAmount
    public var profitLoss: Value
    public var invested: String
    public var entryPrice: String
    public var liquidationPrice: String?
    public var positionSize: String
    public var fundingPayments: Value
    public var activities: [PerpsTradeActivity]
    public var activityTitle: String
    public var isActivityStale = false

    public typealias Value = PerpsValue

    public init(
        id: String, market: PerpsMarketDisplayData, direction: PerpsTradeDirection, leverage: Int,
        equity: BaseCurrencyAmount, profitLoss: Value, invested: String, entryPrice: String,
        liquidationPrice: String?, positionSize: String, fundingPayments: Value,
        activities: [PerpsTradeActivity] = [], activityTitle: String = lang("Activity")
    ) {
        self.id = id
        self.market = market
        self.direction = direction
        self.leverage = leverage
        self.equity = equity
        self.profitLoss = profitLoss
        self.invested = invested
        self.entryPrice = entryPrice
        self.liquidationPrice = liquidationPrice
        self.positionSize = positionSize
        self.fundingPayments = fundingPayments
        self.activities = activities
        self.activityTitle = activityTitle
    }
}

public enum PerpsPositionAction {
    case edit
    case close
    case activity(String)
}
