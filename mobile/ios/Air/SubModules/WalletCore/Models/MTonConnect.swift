
import Foundation
import UIKit
import WalletContext

// REFERENCE:
//     https:github.com/ton-blockchain/ton-connect/blob/main/requests-responses.md#messages


public enum TonConnectErrorCode: Int, Codable {
    case unknownError = 0
    case badRequestError = 1
    case manifestNotFoundError = 2
    case manifestContentError = 3
    case unknownAppError = 100
    case userRejectsError = 300
    case methodNotSupported = 400
}


public struct TonConnectError: Error {
    public var code: TonConnectErrorCode
    
    public init(code: TonConnectErrorCode) {
        self.code = code
    }
}


public enum WalletAction: String, RawRepresentable, Codable {
    case sendTransaction
    case signData
    case disconnect
}


/// All messages from the app to the wallet are requests for an operation. Currently only sendTransaction is supported. signMessage will be supported in the future.
public protocol WalletActionRequest: Equatable, Hashable, Identifiable, Decodable {
    var id: String { get }
    var method: WalletAction { get }
    var params: [String] { get }
}


public func decodeWalletActionRequestsArray(args: Any?) throws -> [any WalletActionRequest] {
    guard let array = args as? [Any] else {
        throw TonConnectError(code: .badRequestError)
    }
    let dataArray = try array.map { any in
        try JSONSerialization.data(withJSONObject: any)
    }
    return try dataArray.map { data in
        try decodeWalletActionRequest(data: data)
    }
}


public func decodeWalletActionRequest(data: Data) throws -> some WalletActionRequest {
    let method = try JSONDecoder().decode(AnyWalletActionRequest.self, from: data).method
    switch method {
    case .sendTransaction:
        return try JSONDecoder().decode(SendTransactionRequest.self, from: data)
    default:
        throw TonConnectError(code: .methodNotSupported)
    }
}


struct AnyWalletActionRequest: Decodable {
    var method: WalletAction
}


public struct SendTransactionRequest: WalletActionRequest {
    public var id: String
    public let method: WalletAction = .sendTransaction
    public var params: [String]
    
    public enum CodingKeys: CodingKey {
        case id
        case method
        case params
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let method = try container.decode(WalletAction.self, forKey: .method)
        if method != .sendTransaction {
            throw DecodingError.dataCorruptedError(forKey: .method, in: container, debugDescription: "expected method = \(WalletAction.sendTransaction.rawValue)")
        }
        self.id = try container.decode(String.self, forKey: .id)
        self.params = try container.decode([String].self, forKey: .params)
    }
}
