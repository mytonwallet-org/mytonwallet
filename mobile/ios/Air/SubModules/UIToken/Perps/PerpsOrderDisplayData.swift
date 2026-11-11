import Foundation
import UIComponents
import WalletCore

public struct PerpsOrderInput: Equatable {
    /// What the amount stands for. The SDK prices a percentage, or a position's current collateral, exactly,
    /// while `amount` shows it in cents.
    public enum Intent: Equatable, Sendable {
        case amount, fraction(Int), current
    }

    public var amount: TradeAmountInput
    public var leverage: Int
    public var intent: Intent
    public var funding: ApiPerpsFundingSource

    public init(amount: String = "", leverage: Int = 2, intent: Intent = .amount,
                funding: ApiPerpsFundingSource = .wallet) {
        self.amount = TradeAmountInput(text: amount)
        self.leverage = leverage
        self.intent = intent
        self.funding = funding
    }

    public var fraction: Int? {
        if case .fraction(let percentage) = intent { return percentage }
        return nil
    }

    /// The typed text contains a nonzero digit; the SDK validates the amount itself.
    public var hasAmount: Bool { amount.text.contains { $0 >= "1" && $0 <= "9" } }
}

/// A presentation snapshot of SDK values for the order screen.
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

    /// SDK estimates for one leverage value of the current draft.
    public struct LeverageEstimate: Equatable {
        public var leverage: Int
        public var liquidationPrice: String?

        public init(leverage: Int, liquidationPrice: String? = nil) {
            self.leverage = leverage
            self.liquidationPrice = liquidationPrice
        }
    }

    /// The adapter supplies the current USD amount and the SDK's classification of the new target.
    public struct EditingPosition {
        public enum Change: Equatable, Sendable { case increase, reduce }
        public let id: String
        /// The current collateral in cents. Entering it leaves the exact collateral unchanged.
        public var currentInput: TradeAmountInput
        /// The exact current collateral that percentages apply to.
        public var currentCollateral: String
        public var currentAmount: String
        public var currentLeverage: Int
        /// The SDK's classification of the quoted draft; nil while unchanged or not yet quoted.
        public var change: Change?
        public var liquidationPrice: String?

        public init(id: String, currentInput: TradeAmountInput, currentCollateral: String, currentAmount: String,
                    currentLeverage: Int, change: Change? = nil, liquidationPrice: String? = nil) {
            self.id = id
            self.currentInput = currentInput
            self.currentCollateral = currentCollateral
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
    public var input: PerpsOrderInput
    /// Largest opening collateral the selected funding source covers. A percentage fills its share in cents at once,
    /// and the SDK prices the exact share.
    public var availableCollateral: TradeAmountInput?
    /// Wallet USDC on Arbitrum.
    public var walletBalance: String?
    /// USDC this asset's book can spend from the Hyperliquid balance; nil when too little to offer it as a payment source.
    public var hyperliquidBalance: String?
    public var editingPosition: EditingPosition?
    public let currency: MBaseCurrency = .USD
    public let currencyDecimals = 2
    public var price = "—"
    public var conversion: String?
    public var paymentAmount: String?
    public var positionSize: String?
    public var bridgeFee: String?
    public var tradingFee: String?
    public var networkFee: String?
    public var fundingRate: String?
    public var fundingRequirement: FundingRequirement?
    public var status: Status = .idle
    public var maxLeverage: Int
    /// Estimates for `input.leverage`, cleared whenever the draft changes.
    public var leverageEstimate: LeverageEstimate?

    public init(token: ApiToken, direction: PerpsTradeDirection, paymentToken: ApiToken,
                input: PerpsOrderInput, maxLeverage: Int) {
        self.token = token
        self.direction = direction
        self.paymentToken = paymentToken
        self.input = input
        self.maxLeverage = maxLeverage
    }

    public var canUseFractions: Bool { editingPosition != nil || availableCollateral != nil }
    /// Leverage values the opening slider offers
    public var leverageRange: ClosedRange<Int> { 1...max(maxLeverage, 1) }

    /// The amount a percentage button fills: a share of the opening balance, or the current collateral
    /// changed by that percentage.
    func amount(forFraction percentage: Int) -> TradeAmountInput? {
        let base = editingPosition?.currentCollateral ?? availableCollateral?.text
        guard let base, let value = Decimal(string: base, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return .cents(value * Decimal(editingPosition == nil ? percentage : 100 + percentage) / 100)
    }
}

extension TradeAmountInput {
    /// `value` in cents, the precision the order screen enters.
    static func cents(_ value: Decimal) -> TradeAmountInput {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return .init(text: rounded > 0 ? "\(rounded)" : "")
    }
}

/// Echo this request when delivering a snapshot. Responses to superseded requests are ignored.
public struct PerpsOrderRequest {
    public enum Action: Equatable {
        case amountChanged, fraction(Int), leverageChanged, fundingChanged, resetAmount, review
        case refreshFunding, buyUsdc, buyEth
    }
    public let id: UUID
    public let action: Action
    public let input: PerpsOrderInput
    public let positionID: String?
}
