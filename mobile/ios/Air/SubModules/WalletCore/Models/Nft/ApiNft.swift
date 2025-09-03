
import Foundation
import WalletContext


// Generated based on TypeScript definition. Do not edit manually.
public struct ApiNft: Equatable, Hashable, Codable, Sendable {
    public var index: Int?
    public var ownerAddress: String?
    public var name: String?
    public var address: String
    public var thumbnail: String?
    public var image: String?
    public var description: String?
    public var collectionName: String?
    public var collectionAddress: String?
    public var isOnSale: Bool
    public var isHidden: Bool?
    public var isOnFragment: Bool?
    public var isTelegramGift: Bool?
    public var isScam: Bool?
    public var metadata: ApiNftMetadata?
}

extension ApiNft {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try? container.decode(Int.self, forKey: .index)
        self.ownerAddress = try? container.decodeIfPresent(String.self, forKey: .ownerAddress)
        self.name = try? container.decodeIfPresent(String.self, forKey: .name)
        self.address = try container.decode(String.self, forKey: .address)
        self.thumbnail = try? container.decode(String.self, forKey: .thumbnail)
        self.image = try? container.decode(String.self, forKey: .image)
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.collectionName = try? container.decodeIfPresent(String.self, forKey: .collectionName)
        self.collectionAddress = try? container.decodeIfPresent(String.self, forKey: .collectionAddress)
        self.isOnSale = (try? container.decodeIfPresent(Bool.self, forKey: .isOnSale)) ?? false
        self.isHidden = try? container.decodeIfPresent(Bool.self, forKey: .isHidden)
        self.isOnFragment = try? container.decodeIfPresent(Bool.self, forKey: .isOnFragment)
        self.isTelegramGift = try? container.decodeIfPresent(Bool.self, forKey: .isTelegramGift)
        self.isScam = try? container.decodeIfPresent(Bool.self, forKey: .isScam)
        self.metadata = try? container.decodeIfPresent(ApiNftMetadata.self, forKey: .metadata)
    }
}

extension ApiNft: Identifiable {
    public var id: String { address }
}

extension ApiNft {
    public static let ERROR = ApiNft(index: 0, address: "error_address", thumbnail: "", image: "", isOnSale: false)
}


public struct ApiNftMetadata: Equatable, Hashable, Codable, Sendable {
    public var attributes: [ApiNftMetadataAttribute]?
    public var lottie: String?
    public var imageUrl: String?
    public var fragmentUrl: String?
    public var mtwCardId: Int?
    public var mtwCardType: ApiMtwCardType?
    public var mtwCardTextType: ApiMtwCardTextType?
    public var mtwCardBorderShineType: ApiMtwCardBorderShineType?
}

extension ApiNftMetadata {
    public var mtwCardBackgroundUrl: URL? {
        if let mtwCardId { return URL(string: "https://static.mytonwallet.org/cards/\(mtwCardId).webp")! }
        return nil
    }
}


// Generated based on TypeScript definition. Do not edit manually.
public enum ApiMtwCardType: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
    case black = "black"
    case platinum = "platinum"
    case gold = "gold"
    case silver = "silver"
    case standard = "standard"
}


// Generated based on TypeScript definition. Do not edit manually.
public enum ApiMtwCardTextType: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
    case light = "light"
    case dark = "dark"
}


// Generated based on TypeScript definition. Do not edit manually.
public enum ApiMtwCardBorderShineType: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
    case up = "up"
    case down = "down"
    case left = "left"
    case right = "right"
    case radioactive = "radioactive"
}

public struct ApiNftMetadataAttribute: Equatable, Hashable, Codable, Sendable {
    public var trait_type: String
    public var value: String
}

// MARK: - Extensions

extension ApiMtwCardType {
    
    public var isPremium: Bool {
        self != .standard
    }
}

extension ApiNft: WEquatable {
    public static func == (lhs: ApiNft, rhs: ApiNft) -> Bool {
        lhs.address == rhs.address
    }
    
    public func isChanged(comparing: ApiNft) -> Bool {
        return isHidden != comparing.isHidden || isOnSale != comparing.isOnSale
    }
}


public extension ApiNft {
    var isStandalone: Bool { collectionName?.nilIfEmpty == nil }
    var displayName: String { name ?? "NFT" }
    static let TON_DNS_COLLECTION_ADDRESS = "EQC3dNlesgVD8YbAazcauIrXBPfiVhMMr5YYk2in0Mtsz0Bz"
    var isTonDns: Bool { collectionAddress == ApiNft.TON_DNS_COLLECTION_ADDRESS }
    var isMtwCard: Bool { metadata?.mtwCardId != nil }
}


#if DEBUG

public extension ApiNft {
    static let sample = ApiNft(
        index: 11,
        ownerAddress: "ownerAddress",
        name: "Name",
        address: "address",
        thumbnail: "https://cache.tonapi.io/imgproxy/cpzE8mRkip07F_buTfatuubNcCIRRQtRGmgRSo5ffc8/rs:fill:1500:1500:1/g:no/aXBmczovL1FtVUJhM291dlh4TDhMRWdHamhweHlaaVgyWEcyUmd4a1hhWlNmdlNmeHBTRXM.webp",
        image: "https://cache.tonapi.io/imgproxy/cpzE8mRkip07F_buTfatuubNcCIRRQtRGmgRSo5ffc8/rs:fill:1500:1500:1/g:no/aXBmczovL1FtVUJhM291dlh4TDhMRWdHamhweHlaaVgyWEcyUmd4a1hhWlNmdlNmeHBTRXM.webp",
        description: "description",
        collectionName: "Collection name",
        collectionAddress: "collectionAddress",
        isOnSale: false,
        isHidden: false,
        isOnFragment: false,
        isScam: false,
        metadata: .init(
            lottie: nil,
            imageUrl: nil,
            fragmentUrl: nil,
            mtwCardId: nil,
            mtwCardType: nil,
            mtwCardTextType: nil,
            mtwCardBorderShineType: nil
        )
    )
    static let sampleMtwCard = try! JSONDecoder().decode(ApiNft.self, fromString: #"{"metadata":{"attributes":[{"trait_type":"trait1","value":"value1"},{"trait_type":"trait2trait2trait2","value":"value2value2value2value2value2value2value2value2"}], "mtwCardId":1806,"mtwCardTextType":"light","mtwCardType":"standard","imageUrl":"https:\/\/static.mytonwallet.org\/cards\/preview\/1806-a5797.jpg","mtwCardBorderShineType":"right"},"isHidden":false,"ownerAddress":"UQCjWIRxnjt45AgA_IXhXnTfzWxBsNOGvM0CC38GOuS6oYs3","name":"MyTonWallet Card #1806","collectionAddress":"EQCQE2L9hfwx1V8sgmF9keraHx1rNK9VmgR1ctVvINBGykyM","isScam":false,"thumbnail":"https:\/\/imgproxy.mytonwallet.org\/imgproxy\/8bKZwRge6Phr-mo_6aMwIToSIG5jh9V6_TT9rsQSLoM\/rs:fill:500:500:1\/g:no\/aHR0cHM6Ly9zdGF0aWMubXl0b253YWxsZXQub3JnL2NhcmRzL3ByZXZpZXcvMTgwNi1hNTc5Ny5qcGc.webp","isOnSale":false,"index":1805,"isOnFragment":false,"image":"https:\/\/imgproxy.mytonwallet.org\/imgproxy\/uOrcShhuNL7T0qbSUHJ-qSVTjFzomgl976mnmpBkmTM\/rs:fill:1500:1500:1\/g:no\/aHR0cHM6Ly9zdGF0aWMubXl0b253YWxsZXQub3JnL2NhcmRzL3ByZXZpZXcvMTgwNi1hNTc5Ny5qcGc.webp","address":"EQC4sLqKTwQOHYckdbkdTNYT17yTtEJqVye1yR7wWkYUIL3u","description":"A sea background MyTonWallet card with purple & yellow desert texture.","collectionName":"MyTonWallet Cards"}"#)
}

#endif
