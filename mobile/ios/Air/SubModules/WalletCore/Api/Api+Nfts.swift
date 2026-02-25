
import Foundation
import WebKit
import WalletContext

extension Api {

    public static func fetchNftByAddress(network: ApiNetwork, nftAddress: String) async throws -> ApiNft? {
        try await bridge.callApiOptional("fetchNftByAddress", network, nftAddress, decodingOptional: ApiNft.self)
    }
    
    public static func fetchNftsFromCollection(accountId: String, collection: ApiNftCollection) async throws {
        try await bridge.callApiVoid("fetchNftsFromCollection", accountId, collection)
    }
    
    public static func checkNftTransferDraft(chain: ApiChain, options: ApiCheckNftTransferDraftOptions) async throws -> ApiCheckTransactionDraftResult {
        try await bridge.callApi("checkNftTransferDraft", chain, options, decoding: ApiCheckTransactionDraftResult.self)
    }

    public static func submitNftTransfers(chain: ApiChain, accountId: String, password: String?, nfts: [ApiNft], toAddress: String, comment: String?, totalRealFee: BigInt?, isNftBurn: Bool?) async throws -> ApiSubmitNftTransfersResult {
        try await bridge.callApi("submitNftTransfers", chain, accountId, password, nfts, toAddress, comment, totalRealFee, isNftBurn, decoding: ApiSubmitNftTransfersResult.self)
    }
    
    public static func checkNftOwnership(chain: ApiChain, accountId: String, nftAddress: String) async throws -> Bool? {
        try await bridge.callApiOptional("checkNftOwnership", chain, accountId, nftAddress, decodingOptional: Bool.self)
    }
}


// MARK: - Types

public struct ApiCheckNftTransferDraftOptions: Encodable {
    public let accountId: String
    public let nfts: [ApiNft]
    public let toAddress: String
    public let comment: String?
    public let isNftBurn: Bool?
    
    public init(accountId: String, nfts: [ApiNft], toAddress: String, comment: String?, isNftBurn: Bool?) {
        self.accountId = accountId
        self.nfts = nfts
        self.toAddress = toAddress
        self.comment = comment
        self.isNftBurn = isNftBurn
    }
}

public struct ApiSubmitNftTransfersResult: Decodable, Sendable {
    public var activityIds: [String]?
    public var error: String?
}
