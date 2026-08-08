
import Foundation
import WebKit
import WalletContext
import WalletCoreTypes

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

    public static func submitNftTransfers(chain: ApiChain, accountId: String, enclaveToken: EnclaveToken?, nfts: [ApiNft], toAddress: String, comment: String?, totalRealFee: BigInt?, isNftBurn: Bool?) async throws -> ApiSubmitNftTransfersResult {
        return try await bridge.callApi("submitNftTransfers", chain, accountId, enclaveToken, nfts, toAddress, comment, totalRealFee, isNftBurn, decoding: ApiSubmitNftTransfersResult.self)
    }
    
    public static func checkNftOwnership(chain: ApiChain, accountId: String, nftAddress: String) async throws -> Bool? {
        try await bridge.callApiOptional("checkNftOwnership", chain, accountId, nftAddress, decodingOptional: Bool.self)
    }

    public static func reportNft(chain: ApiChain, network: ApiNetwork, nftAddress: String) async throws {
        try await bridge.callApiVoid(
            "reportNft",
            ApiReportNftOptions(chain: chain, network: network, nftAddress: nftAddress)
        )
    }
}


// MARK: - Types

public struct ApiCheckNftTransferDraftOptions: Encodable, Sendable {
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

public struct ApiReportNftOptions: Encodable, Sendable {
    public let chain: ApiChain
    public let network: ApiNetwork
    public let nftAddress: String

    public init(chain: ApiChain, network: ApiNetwork, nftAddress: String) {
        self.chain = chain
        self.network = network
        self.nftAddress = nftAddress
    }
}

public struct ApiSubmitNftTransfersResult: Decodable, Sendable {
    public var activityIds: [String]?
    public var mfaRequestHash: String?
    public var error: String?
}

extension ApiSubmitNftTransfersResult: MfaProtectedActionResult {
    public var protectedActionError: String? { error }
}
