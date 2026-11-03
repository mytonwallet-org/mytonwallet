import WalletCore

/// Before-values supplied with a quoted or completed position adjustment.
public struct PerpsPositionChange {
    public var margin: BaseCurrencyAmount
    public var positionSize: String
    public var liquidationPrice: String?

    public init(margin: BaseCurrencyAmount, positionSize: String, liquidationPrice: String?) {
        self.margin = margin
        self.positionSize = positionSize
        self.liquidationPrice = liquidationPrice
    }
}

public struct PerpsPositionClosing {
    public var invested: String
    public var currentValue: String
    public var entryPrice: String

    public init(invested: String, currentValue: String, entryPrice: String) {
        self.invested = invested
        self.currentValue = currentValue
        self.entryPrice = entryPrice
    }
}
