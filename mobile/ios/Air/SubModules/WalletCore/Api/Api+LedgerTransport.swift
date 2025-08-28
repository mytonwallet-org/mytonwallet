

import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func signLedgerTransaction(path: [Int32], transaction: [String: Any]) async throws -> String {
        try await bridge.callApi("signLedgerTransaction", path, AnyEncodable(dict: transaction), decoding: String.self)
    }
}


// MARK: - Types

public struct ApiLedgerTransactionToSign {
    public var to: String
    public var sendMode: SendMode
    public var seqno: Int
    public var timeout: Int
    public var bounce: Bool
    public var amount: BigInt
    public var stateInit: String?
}

public struct SendMode: ExpressibleByIntegerLiteral, Equatable, Hashable, Codable, Sendable, OptionSet {
    
    public static let CARRY_ALL_REMAINING_BALANCE = 128
    public static let CARRY_ALL_REMAINING_INCOMING_VALUE = 64
    public static let DESTROY_ACCOUNT_IF_ZERO = 32
    public static let PAY_GAS_SEPARATELY = 1
    public static let IGNORE_ERRORS = 2
    public static let NONE = 0
    
    public var rawValue: Int
    
    public init() {
        rawValue = 0
    }
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    public init(integerLiteral value: Int) {
        self.rawValue = value
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(Int.self)
    }
}
