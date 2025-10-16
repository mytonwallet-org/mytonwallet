
import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func checkTransactionDraft(chain: ApiChain, options: ApiCheckTransactionDraftOptions) async throws -> ApiCheckTransactionDraftResult {
        do {
            return try await bridge.callApi("checkTransactionDraft", chain, options, decoding: ApiCheckTransactionDraftResult.self)
        } catch {
            if let bridgeError = error as? BridgeCallError, case .message(_, let data) = bridgeError, let data {
                return try JSONSerialization.decode(ApiCheckTransactionDraftResult.self, from: data)
            }
            throw error
        }
    }
    
    public static func submitTransfer(chain: ApiChain, options: ApiSubmitTransferOptions) async throws -> ApiSubmitTransferResult {
        return try await bridge.callApi("submitTransfer", chain, options, decoding: ApiSubmitTransferResult.self)
    }

    /** The goal of the function is acting like `checkTransactionDraft` but return only the diesel information */
    public static func fetchEstimateDiesel(accountId: String, chain: ApiChain, tokenAddress: String) async throws -> ApiFetchEstimateDieselResult? {
        return try await bridge.callApiOptional("fetchEstimateDiesel", accountId, chain, tokenAddress, decodingOptional: ApiFetchEstimateDieselResult.self)
    }
}
