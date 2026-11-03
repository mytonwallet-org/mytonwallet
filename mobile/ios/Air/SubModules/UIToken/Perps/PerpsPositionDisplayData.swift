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
    public var activities: [Activity]
    public var activityTitle: String
    public var isActivityStale = false
    public var canEdit: Bool
    public var canClose: Bool

    public struct Value {
        public enum Tone { case positive, negative, neutral }
        public var text: String
        public var tone: Tone

        public init(_ text: String, tone: Tone = .neutral) {
            self.text = text
            self.tone = tone
        }
    }

    public struct Activity: Identifiable {
        public enum Kind { case opened, increased, reduced, closed, liquidated }
        public var id: String
        public var kind: Kind
        public var title: String
        public var date: String
        public var amount: Value
        public var detail: String
        public var canSelect: Bool

        public init(id: String, kind: Kind, title: String, date: String, amount: Value, detail: String, canSelect: Bool = false) {
            self.id = id
            self.kind = kind
            self.title = title
            self.date = date
            self.amount = amount
            self.detail = detail
            self.canSelect = canSelect
        }
    }

    public init(
        id: String, market: PerpsMarketDisplayData, direction: PerpsTradeDirection, leverage: Int,
        equity: BaseCurrencyAmount, profitLoss: Value, invested: String, entryPrice: String,
        liquidationPrice: String?, positionSize: String, fundingPayments: Value,
        activities: [Activity] = [], canEdit: Bool = false, canClose: Bool = false,
        activityTitle: String = lang("Activity")
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
        self.canEdit = canEdit
        self.canClose = canClose
    }
}

public enum PerpsPositionAction {
    case edit
    case close
    case activity(String)
}
