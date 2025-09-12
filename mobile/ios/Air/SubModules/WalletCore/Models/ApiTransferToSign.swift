
import Foundation
import WalletContext


public protocol ApiTransferToSignProtocol: Equatable, Hashable, Codable, Sendable {
    var toAddress: String { get }
    var amount: BigInt { get }
    var rawPayload: String? { get }
    var payload: ApiParsedPayload? { get }
    var stateInit: String? { get }
}

public struct ApiTransferToSign: ApiTransferToSignProtocol, Equatable, Hashable, Codable, Sendable {
    public var toAddress: String
    public var amount: BigInt
    public var rawPayload: String?
    public var payload: ApiParsedPayload?
    public var stateInit: String?
    
    public init(toAddress: String, amount: BigInt, rawPayload: String? = nil, payload: ApiParsedPayload? = nil, stateInit: String? = nil) {
        self.toAddress = toAddress
        self.amount = amount
        self.rawPayload = rawPayload
        self.payload = payload
        self.stateInit = stateInit
    }
    
    public init<T: ApiTransferToSignProtocol>(_ value: T) {
        self.toAddress = value.toAddress
        self.amount = value.amount
        self.rawPayload = value.rawPayload
        self.payload = value.payload
        self.stateInit = value.stateInit
    }
}
