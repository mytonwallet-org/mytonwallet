
import Foundation
import WalletContext
import Kingfisher
import OrderedCollections

// Generated based on TypeScript definition. Do not edit manually.
public struct ApiNft: Equatable, Hashable, Codable, Sendable {
    public var chain: ApiChain = FALLBACK_CHAIN
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
    public var interface: ApiNftInterface = .default
    public var compression: ApiNftCompression?
    
    public static func == (lhs: ApiNft, rhs: ApiNft) -> Bool {
        lhs.address == rhs.address
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(address)
    }
}

extension ApiNft {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chain = (try? container.decodeIfPresent(ApiChain.self, forKey: .chain)) ?? FALLBACK_CHAIN
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
        self.interface = (try? container.decodeIfPresent(ApiNftInterface.self, forKey: .interface)) ?? .default
        self.compression = try? container.decodeIfPresent(ApiNftCompression.self, forKey: .compression)
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

// Generated based on TypeScript definition. Do not edit manually.
public enum ApiNftInterface: String, Equatable, Hashable, Codable, Sendable, CaseIterable {
    case `default` = "default"
    case compressed = "compressed"
    case mplCore = "mplCore"
}

public struct ApiNftCompression: Equatable, Hashable, Codable, Sendable {
    public var tree: String
    public var dataHash: String
    public var creatorHash: String
    public var leafId: Int
}

extension ApiNftMetadata {
    public var mtwCardBackgroundUrl: URL? {
        if let mtwCardId { return URL(string: "https://static.mytonwallet.org/cards/v2/cards/\(mtwCardId).webp")! }
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

public extension ApiNft {
    var isStandalone: Bool { collectionName?.nilIfEmpty == nil }
    var displayName: String { name ?? "NFT" }
    static let TON_DNS_COLLECTION_ADDRESS = "EQC3dNlesgVD8YbAazcauIrXBPfiVhMMr5YYk2in0Mtsz0Bz"
    var isTonDns: Bool { collectionAddress == ApiNft.TON_DNS_COLLECTION_ADDRESS }
    var isMtwCard: Bool { metadata?.mtwCardId != nil }
}

// MARK: Extract colors

@concurrent public func getAccentColorsFromNfts(nftAddresses: [String], nftsByAddress: OrderedDictionary<String, ApiNft>) async -> [Int: [ApiNft]] {
    let nftAddresses = Set(nftAddresses)
    let candidateNfts: [ApiNft] = nftsByAddress.values
        .filter { nftAddresses.contains($0.address) && $0.collectionAddress == MTW_CARDS_COLLECTION }
    var nftsByColorIndex: [Int: [ApiNft]] = [:]
    let result = await withTaskGroup { group in
        for nft in candidateNfts {
            group.addTask {
                let index = await getAccentColorIndexFromNft(nft: nft)
                return (index, nft)
            }
        }
        for await (index, nft) in group {
            if let index {
                nftsByColorIndex[index, default: []].append(nft)
            }
        }
        return nftsByColorIndex
    }
    return result
}

@concurrent public func getAccentColorIndexFromNft(nft: ApiNft) async -> Int? {
    let mtwCardType = nft.metadata?.mtwCardType
    let mtwCardBorderShineType = nft.metadata?.mtwCardBorderShineType
    
    if mtwCardBorderShineType == .radioactive {
        return ACCENT_RADIOACTIVE_INDEX
    }
    if mtwCardType == .silver {
        return ACCENT_SILVER_INDEX
    }
    if mtwCardType == .gold {
        return ACCENT_GOLD_INDEX
    }
    if mtwCardType == .platinum || mtwCardType == .black {
        return ACCENT_BNW_INDEX
    }
    if let url = nft.metadata?.mtwCardBackgroundUrl,
        let image = try? await ImageDownloader.default.downloadImage(with: url).image,
        let color = image.extractColor()
    {
        let closestColor = closestAccentColor(for: color)
        let index = ACCENT_COLORS.firstIndex(of: closestColor)
        return index
    }
    return nil
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
