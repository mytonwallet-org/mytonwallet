
import Foundation
import WalletContext

public struct NftCollection: Equatable, Hashable, Codable, Identifiable, Sendable, Comparable {
    public var chain: ApiChain
    public var address: String
    public var name: String
    
    public var id: String { "\(chain.rawValue):\(address)" }
    
    public init(chain: ApiChain, address: String, name: String) {
        self.chain = chain
        self.address = address
        self.name = name
    }
    
    public static func < (lhs: NftCollection, rhs: NftCollection) -> Bool {
        if lhs.name != rhs.name {
            return lhs.name < rhs.name
        }
        if lhs.chain != rhs.chain {
            return lhs.chain.rawValue < rhs.chain.rawValue
        }
        return lhs.address < rhs.address
    }
}

extension NftCollection {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.chain = (try? container.decodeIfPresent(ApiChain.self, forKey: .chain)) ?? FALLBACK_CHAIN
        self.address = try container.decode(String.self, forKey: .address)
        self.name = try container.decode(String.self, forKey: .name)
    }
}


extension ApiNft {
    public var collection: NftCollection? {
        if let address = collectionAddress?.nilIfEmpty, let name = collectionName?.nilIfEmpty {
            return NftCollection(chain: chain, address: address, name: name)
        }
        return nil
    }
}
