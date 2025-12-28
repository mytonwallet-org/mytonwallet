
import Foundation
import WalletContext

public protocol DecimalBackingType: Equatable, Hashable, Sendable {
    var decimals: Int { get }
    var displaySymbol: String? { get }
    var forceCurrencyToRight: Bool { get }
    var preferredDecimals: Int? { get }
}

public extension DecimalBackingType {
    var preferredDecimals: Int? { nil }
}

public struct DecimalAmount<Backing: DecimalBackingType>: Equatable, Hashable, Sendable {
    
    public var optionalAmount: BigInt?
    
    public var type: Backing
    
    public var decimals: Int { type.decimals }
    
    public var symbol: String? { type.displaySymbol }
    
    public var forceCurrencyToRight: Bool { type.forceCurrencyToRight }
    
    public init(_ amount: BigInt, _ type: Backing) {
        self.optionalAmount = amount
        self.type = type
    }
}


extension DecimalAmount {
    
    public static func fromDouble(_ doubleValue: Double, _ type: Backing) -> DecimalAmount {
        let amount = doubleToBigInt(doubleValue, decimals: type.decimals)
        return DecimalAmount(amount, type)
    }

    public var roundedForDisplay: DecimalAmount {
        let integer = amount / powI64(10, decimals)
        var rounded = self
        rounded.amount = if integer >= 100_000 {
            roundDecimals(amount, decimals: decimals, roundTo: 2)
        } else if integer >= 10_000 {
            roundDecimals(amount, decimals: decimals, roundTo: 4)
        } else if integer >= 100 {
            roundDecimals(amount, decimals: decimals, roundTo: 6)
        } else {
            amount
        }
        return rounded
    }
    
    public var roundedForSwap: DecimalAmount {
        let doubleValue = self.doubleValue
        var rounded = self
        rounded.amount = if doubleValue >= 1_000_000 {
            roundDecimals(amount, decimals: decimals, roundTo: 0)
        } else if doubleValue >= 100_000 {
            roundDecimals(amount, decimals: decimals, roundTo: 2)
        } else if doubleValue >= 1_000 {
            roundDecimals(amount, decimals: decimals, roundTo: 4)
        } else if doubleValue >= 10 {
            roundDecimals(amount, decimals: decimals, roundTo: 6)
        } else {
            amount
        }
        return rounded
    }
    
    public var doubleValue: Double {
        Double(amount) / pow(Double(10), Double(decimals))
    }
    
    public func convertTo<T: DecimalBackingType>(_ type: T, exchangeRate: Double) -> DecimalAmount<T> {
        let value = self.doubleValue * exchangeRate
        let amount = doubleToBigInt(value, decimals: type.decimals)
        return DecimalAmount<T>(amount, type)
    }
    
    public func switchKeepingDecimalValue<T: DecimalBackingType>(newType: T) -> DecimalAmount<T> {
        let newAmount = convertDecimalsKeepingDoubleValue(amount, fromDecimals: decimals, toDecimals: newType.decimals)
        return DecimalAmount<T>(newAmount, newType)
    }
    
    public var amount: BigInt {
        get { optionalAmount ?? 0 }
        set { optionalAmount = newValue }
    }
}
