
import Foundation
import WalletContext

public struct ApiDappTransfer: ApiTransferToSignProtocol, Equatable, Hashable, Decodable, Sendable {
    
    public var toAddress: String
    public var amount: BigInt
    public var rawPayload: String?
    public var payload: ApiParsedPayload?
    public var stateInit: String?

    public var isScam: Bool?
    /** Whether the transfer should be treated with cautiousness, because its payload is unclear */
    public var isDangerous: Bool
    public var normalizedAddress: String
    /** The transfer address to show in the UI */
    public var displayedToAddress: String
    public var networkFee: BigInt
    
    public init(toAddress: String, amount: BigInt, rawPayload: String? = nil, payload: ApiParsedPayload? = nil, stateInit: String? = nil, isScam: Bool? = nil, isDangerous: Bool, normalizedAddress: String, displayedToAddress: String, networkFee: BigInt) {
        self.toAddress = toAddress
        self.amount = amount
        self.rawPayload = rawPayload
        self.payload = payload
        self.stateInit = stateInit
        self.isScam = isScam
        self.isDangerous = isDangerous
        self.normalizedAddress = normalizedAddress
        self.displayedToAddress = displayedToAddress
        self.networkFee = networkFee
    }
}

