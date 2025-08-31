
import Foundation
import WalletContext


public struct DecimalAmountFormatStyle<Kind: DecimalBackingType>: FormatStyle {
    
    public typealias FormatInput = DecimalAmount<Kind>
    public typealias FormatOutput = String
    
    public var maxDecimals: Int?
    public var showPlus: Bool
    public var showMinus: Bool
    public var roundUp: Bool
    public var precision: MFee.FeePrecision?
    
    public init(maxDecimals: Int? = nil, showPlus: Bool = false, showMinus: Bool = true, roundUp: Bool = true, precision: MFee.FeePrecision? = nil) {
        self.maxDecimals = maxDecimals
        self.showPlus = showPlus
        self.showMinus = showMinus
        self.roundUp = roundUp
        self.precision = precision
    }
    
    public func format(_ value: FormatInput) -> String {
        
        let prefix = precision?.prefix ?? ""
        return prefix + formatBigIntText(
            value.amount,
            currency: value.symbol,
            negativeSign: showMinus,
            positiveSign: showPlus,
            tokenDecimals: value.decimals,
            decimalsCount: maxDecimals,
            forceCurrencyToRight: value.forceCurrencyToRight,
            roundUp: roundUp
        )
    }
}


extension DecimalAmount {
    public func formatted(maxDecimals: Int? = nil, showPlus: Bool = false, showMinus: Bool = true, roundUp: Bool = true, precision: MFee.FeePrecision? = nil) -> String {
        DecimalAmountFormatStyle(maxDecimals: maxDecimals, showPlus: showPlus, showMinus: showMinus, roundUp: roundUp, precision: precision).format(self)
    }
}


extension DecimalAmount: CustomStringConvertible {
    public var description: String {
        self.formatted()
    }
}
