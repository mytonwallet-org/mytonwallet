
import WalletContext

extension ApiUpdate {
    public struct UpdateNfts: Equatable, Hashable, Codable, Sendable {
        public var type = "updateNfts"
        public var accountId: String
        public var nfts: [ApiNft]
        public var chain: ApiChain
        public var collectionAddress: String?
        public var isFullLoading: Bool?
        /** Complete set of addresses seen during a streaming session. Sent with the final `isFullLoading: false` update. */
        public var streamedAddresses: [String]?
    }
    
    public struct NftReceived: Equatable, Hashable, Codable, Sendable {
        public var type = "nftReceived"
        public var accountId: String
        public var nftAddress: String
        public var nft: ApiNft
    }
    
    public struct NftSent: Equatable, Hashable, Codable, Sendable {
        public var type = "nftSent"
        public var accountId: String
        public var nftAddress: String
        public var newOwnerAddress: String
    }
    
    public struct NftPutUpForSale: Equatable, Hashable, Codable, Sendable {
        public var type = "nftPutUpForSale"
        public var accountId: String
        public var nftAddress: String
    }
}
