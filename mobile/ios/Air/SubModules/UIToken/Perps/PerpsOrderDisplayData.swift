import Foundation
import UIComponents
import WalletCore

public struct PerpsOrderInput: Equatable {
    public var amount: TradeAmountInput
    public var leverage: Int
    public var leverageOnly: Bool

    public init(amount: String = "", leverage: Int = 2, leverageOnly: Bool = false) {
        self.amount = TradeAmountInput(text: amount)
        self.leverage = leverage
        self.leverageOnly = leverageOnly
    }

    /// Text presentation only. Decimal amounts and order validity are resolved by the adapter.
    public var hasAmount: Bool { amount.text.contains { $0 >= "1" && $0 <= "9" } }
}

/// A complete presentation snapshot. No fetching, conversion, fee or liquidation calculations live in the UI.
public struct PerpsOrderDisplayData {
    public enum Status: Equatable {
        case idle, loading, ready
        case unavailable(String)
    }

    public enum FundingAction: Equatable, Sendable {
        case buyUsdc, buyEth
    }

    public struct FundingRequirement: Equatable {
        public let title: String
        public let message: String
        public let buttonTitle: String
        public let actionTitle: String
        public let action: FundingAction

        public init(title: String, message: String, buttonTitle: String, actionTitle: String, action: FundingAction) {
            self.title = title
            self.message = message
            self.buttonTitle = buttonTitle
            self.actionTitle = actionTitle
            self.action = action
        }
    }

    public struct LeverageOption {
        public var value: Int
        public var liquidationPrice: String?
        public var paymentAmount: String?
        public var warning: String?
        public var isPreset: Bool

        public init(value: Int, liquidationPrice: String? = nil, paymentAmount: String? = nil, warning: String? = nil, isPreset: Bool = false) {
            self.value = value
            self.liquidationPrice = liquidationPrice
            self.paymentAmount = paymentAmount
            self.warning = warning
            self.isPreset = isPreset
        }
    }

    /// The adapter supplies the current USD amount and classifies the new target.
    public struct EditingPosition {
        public enum Change: Equatable, Sendable { case increase, reduce, leverage }
        public let id: String
        public var currentInput: TradeAmountInput
        public var currentAmount: String
        public var currentLeverage: Int?
        /// nil means unchanged or not yet quoted. The UI never compares financial values.
        public var change: Change?
        public var liquidationPrice: String?

        public init(id: String, currentInput: TradeAmountInput, currentAmount: String,
                    change: Change? = nil, liquidationPrice: String? = nil, currentLeverage: Int? = nil) {
            self.id = id
            self.currentInput = currentInput
            self.currentAmount = currentAmount
            self.currentLeverage = currentLeverage
            self.change = change
            self.liquidationPrice = liquidationPrice
        }
    }

    public var token: ApiToken
    public var direction: PerpsTradeDirection
    public var paymentToken: ApiToken
    public var account: MAccount?
    public var canSelectAccount = false
    public var input: PerpsOrderInput
    public var availableCollateral: TradeAmountInput?
    public var editingPosition: EditingPosition?
    public var currency: MBaseCurrency = .USD
    public var currencyDecimals = 2
    public var price = "—"
    public var conversion: String?
    public var paymentAmount: String?
    public var positionSize: String?
    public var swapFee: String?
    public var tradingFee: String?
    public var networkFee: String?
    public var fundingPayments: String?
    public var fundingRequirement: FundingRequirement?
    public var status: Status = .idle
    public var canUseFractions = false
    public var canSelectPayment = true
    /// Supported values, in increasing order, with estimates supplied by the adapter for the current draft.
    public var leverageOptions: [LeverageOption] = []

    public init(token: ApiToken, direction: PerpsTradeDirection, paymentToken: ApiToken,
                input: PerpsOrderInput = .init()) {
        self.token = token
        self.direction = direction
        self.paymentToken = paymentToken
        self.input = input
    }
}

/// Echo this request when delivering a snapshot. Responses to superseded requests are ignored.
public struct PerpsOrderRequest {
    public enum Action: Equatable {
        case amountChanged, fraction(Int), selectPayment, selectAccount, leverageChanged, resetAmount, review
        case refreshFunding, buyUsdc, buyEth
    }
    public let id: UUID
    public let action: Action
    public let input: PerpsOrderInput
    public let positionID: String?
}
