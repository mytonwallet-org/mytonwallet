
import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func fetchPastActivities(accountId: String, limit: Int, tokenSlug: String?, toTimestamp: Int64?) async throws -> [ApiActivity] {
        try await bridge.callApi("fetchPastActivities", accountId, limit, tokenSlug, toTimestamp, decoding: [ApiActivity].self)
    }
    
    public static func submitTransfer(chain: ApiChain, options: Api.SubmitTransferOptions, shouldCreateLocalActivity: Bool? = nil) async throws -> ApiSubmitTransferResult {
        print(options)
        return try await bridge.callApi("submitTransfer", chain, options, shouldCreateLocalActivity, decoding: ApiSubmitTransferResult.self)
    }
    
    /// - Important: call through ActivityStore
    internal static func fetchTonActivityDetails(accountId: String, activity: ApiActivity) async throws -> ApiActivity {
        try await bridge.callApi("fetchTonActivityDetails", accountId, activity, decoding: ApiActivity.self)
    }
    
    public static func decryptComment(accountId: String, encryptedComment: String, fromAddress: String, password: String) async throws -> String {
        try await bridge.callApi("decryptComment", accountId, encryptedComment, fromAddress, password, decoding: String.self)
    }
    
    public static func checkTransactionDraft(chain: String, options: CheckTransactionDraftOptions) async throws -> MTransactionDraft {
        do {
            return try await bridge.callApi("checkTransactionDraft", chain, options, decoding: MTransactionDraft.self)
        } catch {
            if let bridgeError = error as? BridgeCallError, case .message(_, let data) = bridgeError, let data {
                return try JSONSerialization.decode(MTransactionDraft.self, from: data)
            }
            throw error
        }
    }
    
    // MARK: Callback methods
    
    /// - Note: `shouldCreateLocalTransaction = true`
    public static func submitTransfer(chain: String,
                                      options: SubmitTransferOptions,
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

public struct ApiSubmitTransferResult: Decodable, Sendable {
    public var error: String?
}

