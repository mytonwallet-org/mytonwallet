
import Foundation
import WalletContext

public struct DecimalAmountFormatStyle<Kind: DecimalBackingType>: FormatStyle {
    
    public typealias FormatInput = DecimalAmount<Kind>
    public typealias FormatOutput = String
    
    public var adaptivePreset: AdaptivePreset<Kind>?
    public var maxDecimals: Int?
    public var showPlus: Bool
    public var showMinus: Bool
    public var roundUp: Bool
    public var precision: MFee.FeePrecision?
    public var showSymbol: Bool
    
    public init(preset: AdaptivePreset<Kind>? = nil, maxDecimals: Int? = nil, showPlus: Bool = false, showMinus: Bool = true, roundUp: Bool = true, precision: MFee.FeePrecision? = nil, showSymbol: Bool = true) {
        self.adaptivePreset = preset
        self.maxDecimals = maxDecimals
        self.showPlus = showPlus
        self.showMinus = showMinus
        self.roundUp = roundUp
        self.precision = precision
        self.showSymbol = showSymbol
    }
    
    public func format(_ value: FormatInput) -> String {
        let prefix = precision?.prefix ?? ""
        let maxDecimals = adaptivePreset?.resolve(value) ?? maxDecimals
        return prefix + formatBigIntText(
            value.amount,
            currency: showSymbol ? value.symbol : nil,
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
    public func formatted(_ preset: AdaptivePreset<Backing>?, maxDecimals: Int? = nil, showPlus: Bool = false, showMinus: Bool = true, roundUp: Bool = true, precision: MFee.FeePrecision? = nil) -> String {
        DecimalAmountFormatStyle(preset: preset, maxDecimals: maxDecimals, showPlus: showPlus, showMinus: showMinus, roundUp: roundUp, precision: precision).format(self)
    }
}

extension DecimalAmount: CustomStringConvertible {
    public var description: String {
        self.formatted(.none)
    }
}
