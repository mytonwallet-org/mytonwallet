
import Foundation
import WalletContext

/// Double represented as number or string
public struct MDouble: Equatable, Hashable, Codable, Sendable, Comparable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, CustomStringConvertible {
    
    public var value: Double
    
    public var stringValue: String { String(value) }
    
    public init(_ value: Double) {
        self.value = value
    }
    
    public init(floatLiteral value: Double) {
        self.value = value
    }
    
    public init(integerLiteral value: Int) {
        self.value = Double(value)
    }
    
    public init?(_ stringValue: String) {
        if let value = Double(stringValue) {
            self.value = value
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
        do {
            self.value = try container.decode(Double.self)
        } catch {
            self.value = try Double(container.decode(String.self)).orThrow()
        }
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.stringValue)
    }
    
    public static func < (lhs: MDouble, rhs: MDouble) -> Bool {
        lhs.value < rhs.value
    }
    
    public var description: String { stringValue }
}
