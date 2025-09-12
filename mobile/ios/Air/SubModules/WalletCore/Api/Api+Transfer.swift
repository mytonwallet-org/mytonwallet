
import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func checkTransactionDraft(chain: ApiChain, options: ApiCheckTransactionDraftOptions) async throws -> MTransactionDraft {
        do {
            return try await bridge.callApi("checkTransactionDraft", chain, options, decoding: MTransactionDraft.self)
        } catch {
            if let bridgeError = error as? BridgeCallError, case .message(_, let data) = bridgeError, let data {
                return try JSONSerialization.decode(MTransactionDraft.self, from: data)
            }
            throw error
        }
    }
    
    public static func submitTransfer(chain: ApiChain, options: ApiSubmitTransferOptions, shouldCreateLocalActivity: Bool? = nil) async throws -> ApiSubmitTransferResult {
        return try await bridge.callApi("submitTransfer", chain, options, shouldCreateLocalActivity, decoding: ApiSubmitTransferResult.self)
    }
    
    // MARK: Callback methods
    
    /// - Note: `shouldCreateLocalTransaction = true`
    @available(*, deprecated)
    public static func submitTransfer(chain: ApiChain,
                                      options: ApiSubmitTransferOptions,
                                      callback: @escaping (Result<(String), BridgeCallError>) -> Void) {
        shared?.webViewBridge.callApi(methodName: "submitTransfer", args: [
            AnyEncodable(chain),
            AnyEncodable(options),
        ]) { result in
            switch result {
            case .success(let response):
                callback(.success((response as? [String: Any])?["txId"] as? String ?? ""))
            case .failure(let failure):
                callback(.failure(failure))
            }
        }
    }
}


// MARK: - Types

public struct ApiCheckTransactionDraftOptions: Encodable, Sendable {
    public var accountId: String
    public var toAddress: String
    public var amount: BigInt?
    public var tokenAddress: String?
    /// - Note: `data?: string | Uint8Array | Cell;`
    public var data: String?
    public var stateInit: String?
    public var shouldEncrypt: Bool?
    public var isBase64Data: Bool?
    public var forwardAmount: BigInt?
    public var allowGasless: Bool?
    
    public init(accountId: String, toAddress: String, amount: BigInt?, tokenAddress: String?, data: String?, stateInit: String?, shouldEncrypt: Bool?, isBase64Data: Bool?, forwardAmount: BigInt?, allowGasless: Bool?) {
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

public struct ApiSubmitTransferOptions: Encodable, Sendable {
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
    public let isGaslessWithStars: Bool?
    public let forwardAmount: BigInt?
    public let noFeeCheck: Bool?
    
    public init(accountId: String, password: String? = nil, toAddress: String, amount: BigInt, comment: String?, tokenAddress: String?, fee: BigInt?, realFee: BigInt?, shouldEncrypt: Bool?, isBase64Data: Bool?, withDiesel: Bool?, dieselAmount: BigInt?, stateInit: String?, isGaslessWithStars: Bool?, forwardAmount: BigInt?, noFeeCheck: Bool?) {
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
        self.isGaslessWithStars = isGaslessWithStars
        self.forwardAmount = forwardAmount
        self.noFeeCheck = noFeeCheck
    }
}

public struct ApiSubmitTransferResult: Decodable, Sendable {
    public var error: String?
}

