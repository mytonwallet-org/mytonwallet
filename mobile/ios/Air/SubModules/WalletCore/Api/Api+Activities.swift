
import Foundation
import WebKit
import WalletContext

extension Api {
    
    public static func fetchPastActivities(accountId: String, limit: Int, tokenSlug: String?, toTimestamp: Int64?) async throws -> ApiActivitySliceResult {
        try await bridge.callApi("fetchPastActivities", accountId, limit, tokenSlug, toTimestamp, decoding: ApiActivitySliceResult.self)
    }
    
    public static func decryptComment(accountId: String, activity: ApiTransactionActivity, password: String?) async throws -> String {
        try await bridge.callApi("decryptComment", accountId, activity, password, decoding: String.self)
    }

    /// - Important: call through ActivityStore
    internal static func fetchActivityDetails(accountId: String, activity: ApiActivity) async throws -> ApiActivity {
        try await bridge.callApi("fetchActivityDetails", accountId, activity, decoding: ApiActivity.self)
    }
    
    public static func fetchTransactionById(chain: ApiChain, network: ApiNetwork, txId: String, walletAddress: String) async throws -> [ApiActivity] {
        let options = ApiFetchTransactionByIdOptions(chain: chain, network: network, walletAddress: walletAddress, txId: txId)
        return try await bridge.callApi("fetchTransactionById", options, decoding: [ApiActivity].self)
    }

    public static func fetchTransactionById(chain: ApiChain, network: ApiNetwork, txHash: String, walletAddress: String) async throws -> [ApiActivity] {
        let options = ApiFetchTransactionByIdOptions(chain: chain, network: network, walletAddress: walletAddress, txHash: txHash)
        return try await bridge.callApi("fetchTransactionById", options, decoding: [ApiActivity].self)
    }
}

private struct ApiFetchTransactionByIdOptions: Encodable {
    var chain: ApiChain
    var network: ApiNetwork
    var walletAddress: String
    var txId: String?
    var txHash: String?
}

public struct ApiActivitySliceResult: Codable, Sendable {
    public let activities: [ApiActivity]
    public let shouldFetchMore: Bool
}
