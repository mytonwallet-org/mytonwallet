
import Foundation
import WalletContext

public struct ApiSubmitTransferOptions: ApiTransactionCommonOptions, Equatable, Hashable, Codable, Sendable {
    
    // ApiTransactionCommonOptions
    public var accountId: String
    public var toAddress: String
    /// Must be set (this can't be encoded with Swift type system)
    public var amount: BigInt?
    public var payload: AnyTransferPayload?
    public var stateInit: String?
    /// Must be set for gasless transfer (this can't be encoded with Swift type system)
    public var tokenAddress: String?
    
    // ApiSubmitTransferOptions
    /**
    * The `realFee` obtained earlier from the `checkTransactionDraft` method. Measured in the native token.
    * To show in the created local transaction.
    */
    public var realFee: BigInt?
    public var isGasless: Bool?
    /// Must be set for gasless transfer (this can't be encoded with Swift type system)
    public var dieselAmount: BigInt?
    public var isGaslessWithStars: Bool?
    
    // ApiSubmitGasfullTransferOptions
      /** Required only for mnemonic accounts */
    public var password: String?
    /** To cap the fee in TRON transfers */
    public var fee: BigInt?
    public var noFeeCheck: Bool?
    
    // ApiSubmitGaslessTransferOptions
    // nothing here, see comments about optionality above
    
    public init(accountId: String, toAddress: String, amount: BigInt, payload: AnyTransferPayload?, stateInit: String?, tokenAddress: String?, realFee: BigInt?, isGasless: Bool?, dieselAmount: BigInt?, isGaslessWithStars: Bool?, password: String?, fee: BigInt?, noFeeCheck: Bool?) {
        self.accountId = accountId
        self.toAddress = toAddress
        self.amount = amount
        self.payload = payload
        self.stateInit = stateInit
        self.tokenAddress = tokenAddress
        self.realFee = realFee
        self.isGasless = isGasless
        self.dieselAmount = dieselAmount
        self.isGaslessWithStars = isGaslessWithStars
        self.password = password
        self.fee = fee
        self.noFeeCheck = noFeeCheck
    }
}
