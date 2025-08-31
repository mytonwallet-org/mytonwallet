
import Foundation
import WalletContext

extension Api {

    public struct CheckTransactionDraftOptions: Encodable, Sendable {
        let accountId: String
        let toAddress: String
        // TODO: Make sure nil value is ok
        /// - Note: `amount?: bigint;`
        /// - Warning: **Nil value currently unsupported:** When the value is undefined, the method doesn't check the available balance. If you want only to estimate the fee, don't send the amount, because: a) The fee doesn't depend on the amount neither in TON nor in TRON. b) Errors will happen in edge cases such as 0 and greater than the balance.
        public let amount: BigInt
        let tokenAddress: String?
        /// - Note: `data?: string | Uint8Array | Cell;`
        let data: String?
        let stateInit: String?
        let shouldEncrypt: Bool?
        let isBase64Data: Bool?
        let forwardAmount: BigInt?
        let allowGasless: Bool?
        
        public init(accountId: String, toAddress: String, amount: BigInt, tokenAddress: String?, data: String?, stateInit: String?, shouldEncrypt: Bool?, isBase64Data: Bool?, forwardAmount: BigInt?, allowGasless: Bool?) {
            self.accountId = accountId
            self.toAddress = toAddress
            self.amount = amount
            self.tokenAddress = tokenAddress
            self.data = data
            self.stateInit = stateInit
            self.shouldEncrypt = shouldEncrypt
            self.isBase64Data = isBase64Data
            self.forwardAmount = forwardAmount
            self.allowGasless = allowGasless
        }
    }
    
    public struct SubmitTransferOptions: Encodable, Sendable {
        public let accountId: String
        /** Required only for mnemonic accounts */
        public var password: String?
        public let toAddress: String
        public let amount: BigInt
        public let comment: String?
        public let tokenAddress: String?
        /// To cap the fee in TRON transfers
        public let fee: BigInt?
        /// To show in the created local transaction
        public let realFee: BigInt?
        public let shouldEncrypt: Bool?
        public let isBase64Data: Bool?
        public let withDiesel: Bool?
        public let dieselAmount: BigInt?
        /// - Note: `stateInit?: string | Cell;`
        public let stateInit: String?
        public let forwardAmount: BigInt?
        public let noFeeCheck: Bool?
        
        public init(accountId: String, password: String? = nil, toAddress: String, amount: BigInt, comment: String?, tokenAddress: String?, fee: BigInt?, realFee: BigInt?, shouldEncrypt: Bool?, isBase64Data: Bool?, withDiesel: Bool?, dieselAmount: BigInt?, stateInit: String?, forwardAmount: BigInt?, noFeeCheck: Bool?) {
            self.accountId = accountId
            self.password = password
            self.toAddress = toAddress
            self.amount = amount
            self.comment = comment
            self.tokenAddress = tokenAddress
            self.fee = fee
            self.realFee = realFee
            self.shouldEncrypt = shouldEncrypt
            self.isBase64Data = isBase64Data
            self.withDiesel = withDiesel
            self.dieselAmount = dieselAmount
            self.stateInit = stateInit
            self.forwardAmount = forwardAmount
            self.noFeeCheck = noFeeCheck
        }
    }
}

public typealias ApiSubmitTransferOptions = Api.SubmitTransferOptions
