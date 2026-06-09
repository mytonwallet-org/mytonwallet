
import Foundation
import WalletContext

/// Double represented as number or string
public struct MDouble: Equatable, Hashable, Codable, Sendable, Comparable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, CustomStringConvertible {
    
    public var value: Double
    private var exactStringValue: String?
    
    public var stringValue: String { exactStringValue ?? String(value) }
    
    public init(_ value: Double) {
        self.value = value
        self.exactStringValue = nil
    }
    
    public init(floatLiteral value: Double) {
        self.value = value
        self.exactStringValue = nil
    }
    
    public init(integerLiteral value: Int) {
        self.value = Double(value)
        self.exactStringValue = nil
    }
    
    public init?(_ stringValue: String) {
        if let value = Double(stringValue) {
            self.value = value
            self.exactStringValue = stringValue
        } else {
            return nil
        }
    }
    
    public static func forBigInt(_ amount: BigInt, decimals: Int) -> MDouble? {
        let string = bigIntToDoubleString(amount, decimals: decimals)
        return MDouble(string)
    }
    
    public static let zero = MDouble(0)
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self.value = try Double(stringValue).orThrow()
            self.exactStringValue = stringValue
        } else {
            self.value = try container.decode(Double.self)
            self.exactStringValue = nil
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.stringValue)
    }

    public func bigintAmount(decimals: Int) -> BigInt {
        if let exactStringValue {
            return amountValue(exactStringValue, digits: decimals)
        }
        return doubleToBigInt(value, decimals: decimals)
    }
    
    public static func == (lhs: MDouble, rhs: MDouble) -> Bool {
        lhs.value == rhs.value
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }
    
    public static func < (lhs: MDouble, rhs: MDouble) -> Bool {
        lhs.value < rhs.value
    }
    
    public var description: String { stringValue }
}
