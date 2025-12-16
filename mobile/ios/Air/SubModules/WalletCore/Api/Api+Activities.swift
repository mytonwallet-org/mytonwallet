
import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func fetchPastActivities(accountId: String, limit: Int, tokenSlug: String?, toTimestamp: Int64?) async throws -> [ApiActivity] {
        try await bridge.callApi("fetchPastActivities", accountId, limit, tokenSlug, toTimestamp, decoding: [ApiActivity].self)
    }
    
    public static func decryptComment(accountId: String, activity: ApiTransactionActivity, password: String?) async throws -> String {
        try await bridge.callApi("decryptComment", accountId, activity, password, decoding: String.self)
    }

    /// - Important: call through ActivityStore
    internal static func fetchActivityDetails(accountId: String, activity: ApiActivity) async throws -> ApiActivity {
        try await bridge.callApi("fetchActivityDetails", accountId, activity, decoding: ApiActivity.self)
    }
    
    public static func fetchTransactionById(chain: ApiChain, network: ApiNetwork, txHash: String, walletAddress: String) async throws -> [ApiActivity] {
        try await bridge.callApi("fetchTransactionById", chain, network, txHash, walletAddress, decoding: [ApiActivity].self)
    }
}
