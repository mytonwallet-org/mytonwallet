
import Foundation
import WalletContext

public struct ApiCheckTransactionDraftOptions: ApiTransactionCommonOptions, Equatable, Hashable, Codable, Sendable {
    
    // ApiTransactionCommonOptions
    public var accountId: String
    public var toAddress: String
    public var amount: BigInt?
    public var payload: AnyTransferPayload?
    public var stateInit: String?
    public var tokenAddress: String?
    
    // specific to ApiCheckTransactionDraftOptions
    public var allowGasless: Bool?
    
    public init(accountId: String, toAddress: String, amount: BigInt?, payload: AnyTransferPayload?, stateInit: String?, tokenAddress: String?, allowGasless: Bool?) {
        self.accountId = accountId
        self.toAddress = toAddress
        self.amount = amount
        self.payload = payload
        self.stateInit = stateInit
        self.tokenAddress = tokenAddress
        self.allowGasless = allowGasless
    }
}
