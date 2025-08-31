
import WalletContext

extension ApiUpdate {
    public struct UpdateNfts: Equatable, Hashable, Codable, Sendable {
        public var type = "updateNfts"
        public var accountId: String
        public var nfts: [ApiNft]
    }
    
    public struct NftReceived: Equatable, Hashable, Codable, Sendable {
        public let type = "nftReceived"
        public var accountId: String
        public var nftAddress: String
        public var nft: ApiNft
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.nftAddress = try container.decode(String.self, forKey: .nftAddress)
            self.nft = try container.decode(ApiNft.self, forKey: .nft)
        }
    }
    
    public struct NftSent: Equatable, Hashable, Codable, Sendable {
        public let type = "nftSent"
        public var accountId: String
        public var nftAddress: String
        public var newOwnerAddress: String
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.nftAddress = try container.decode(String.self, forKey: .nftAddress)
            self.newOwnerAddress = try container.decode(String.self, forKey: .newOwnerAddress)
        }
    }
    
    public struct NftPutUpForSale: Equatable, Hashable, Codable, Sendable {
        public let type = "nftPutUpForSale"
        public var accountId: String
        public var nftAddress: String
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.accountId = try container.decode(String.self, forKey: .accountId)
            self.nftAddress = try container.decode(String.self, forKey: .nftAddress)
        }
    }
}
