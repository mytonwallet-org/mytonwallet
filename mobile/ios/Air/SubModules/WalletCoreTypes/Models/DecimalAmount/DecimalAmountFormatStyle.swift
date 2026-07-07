
import Foundation
import WalletContext

public enum DecimalAmountFormatPrecision: String, Codable, Sendable {
    case exact = "exact"
    case approximate = "approximate"
    case lessThan = "lessThan"
    
    public var prefix: String {
        switch self {
        case .exact:
            return ""
        case .approximate:
            return "~"
        case .lessThan:
            return "< "
        }
    }
}

public struct DecimalAmountFormatStyle<Kind: DecimalBackingType>: FormatStyle {
    
    public typealias FormatInput = DecimalAmount<Kind>
    public typealias FormatOutput = String
    
    public var adaptivePreset: AdaptivePreset<Kind>?
    public var maxDecimals: Int?
    public var showPlus: Bool
    public var showMinus: Bool
    public var roundHalfUp: Bool
    public var precision: DecimalAmountFormatPrecision?
    public var showSymbol: Bool
    public var zeroCountSubscriptMinCount: Int?
    
    public init(
        preset: AdaptivePreset<Kind>? = nil,
        maxDecimals: Int? = nil,
        showPlus: Bool = false,
        showMinus: Bool = true,
        roundHalfUp: Bool = true,
        precision: DecimalAmountFormatPrecision? = nil,
        showSymbol: Bool = true,
        zeroCountSubscriptMinCount: Int? = nil
    ) {
        self.adaptivePreset = preset
        self.maxDecimals = maxDecimals
        self.showPlus = showPlus
        self.showMinus = showMinus
        self.roundHalfUp = roundHalfUp
        self.precision = precision
        self.showSymbol = showSymbol
        self.zeroCountSubscriptMinCount = zeroCountSubscriptMinCount
    }
    
    public func format(_ value: FormatInput) -> String {
        let prefix = precision?.prefix ?? ""
        let maxDecimals = adaptivePreset?.resolve(value) ?? maxDecimals
        let zeroCountSubscriptMinCount = zeroCountSubscriptMinCount ?? adaptivePreset?.zeroCountSubscriptMinCount
        return prefix + formatBigIntText(
            value.amount,
            currency: showSymbol ? value.symbol : nil,
            negativeSign: showMinus,
            positiveSign: showPlus,
            tokenDecimals: value.decimals,
            decimalsCount: maxDecimals,
            forceCurrencyToRight: value.forceCurrencyToRight,
            roundHalfUp: roundHalfUp,
            isShortened: adaptivePreset == .baseCurrencyEquivalentShortened,
            zeroCountSubscriptMinCount: zeroCountSubscriptMinCount
        )
    }
}

extension DecimalAmount {
    public func formatted(
        _ preset: AdaptivePreset<Backing>?,
        maxDecimals: Int? = nil,
        showPlus: Bool = false,
        showMinus: Bool = true,
        roundHalfUp: Bool = true,
        precision: DecimalAmountFormatPrecision? = nil,
        zeroCountSubscriptMinCount: Int? = nil
    ) -> String {
        DecimalAmountFormatStyle(
            preset: preset,
            maxDecimals: maxDecimals,
            showPlus: showPlus,
            showMinus: showMinus,
            roundHalfUp: roundHalfUp,
            precision: precision,
            zeroCountSubscriptMinCount: zeroCountSubscriptMinCount
        ).format(self)
    }
}

extension DecimalAmount: CustomStringConvertible {
    public var description: String {
        self.formatted(.none)
    }
}
