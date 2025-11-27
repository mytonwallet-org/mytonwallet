
import Foundation
import WalletContext

// MARK: ApiToken

extension ApiToken: DecimalBackingType {
    public var displaySymbol: String? { symbol }
    public var forceCurrencyToRight: Bool { true }
}

extension DecimalAmount where Backing == ApiToken {
    public var token: ApiToken {
        get { type }
        set { type = newValue }
    }
}

public typealias TokenAmount = DecimalAmount<ApiToken>


// MARK: MBaseCurrency

extension MBaseCurrency: DecimalBackingType {
    public var decimals: Int { decimalsCount }
    public var displaySymbol: String? { sign }
    public var forceCurrencyToRight: Bool { sign == "₽" }
}

extension DecimalAmount where Backing == MBaseCurrency {
    public var baseCurrency: MBaseCurrency { type }
}

extension DecimalAmount where Backing == MBaseCurrency {
    public static func baseCurrency(_ amount: BigInt) -> DecimalAmount? {        
        let baseCurrency = TokenStore.baseCurrency
        return DecimalAmount(amount, baseCurrency)
    }
}

public typealias BaseCurrencyAmount = DecimalAmount<MBaseCurrency>


// MARK: AnyDecimalBackingType

public struct AnyDecimalBackingType: DecimalBackingType {
    public var decimals: Int
    public var displaySymbol: String?
    public var forceCurrencyToRight: Bool
    public init(decimals: Int, displaySymbol: String?, forceCurrencyToRight: Bool) {
        self.decimals = decimals
        self.displaySymbol = displaySymbol
        self.forceCurrencyToRight = forceCurrencyToRight
    }
}

extension DecimalAmount where Backing == AnyDecimalBackingType {
    public init(_ amount: BigInt, decimals: Int, symbol: String?, forceCurrencyToRight: Bool = false) {
        self.optionalAmount = amount
        self.type = AnyDecimalBackingType(decimals: decimals, displaySymbol: symbol, forceCurrencyToRight: forceCurrencyToRight)
    }
}

public typealias AnyDecimalAmount = DecimalAmount<AnyDecimalBackingType>
