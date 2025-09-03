
import Foundation
import WalletContext

public struct NftCollection: Equatable, Hashable, Codable, Identifiable, Sendable, Comparable {
    public var address: String
    public var name: String
    
    public var id: String { address }
    
    public init(address: String, name: String) {
        self.address = address
        self.name = name
    }
    
    public static func < (lhs: NftCollection, rhs: NftCollection) -> Bool {
        lhs.name < rhs.name
    }
}


extension ApiNft {
    public var collection: NftCollection? {
        if let address = collectionAddress?.nilIfEmpty, let name = collectionName?.nilIfEmpty {
            return NftCollection(address: address, name: name)
        }
        return nil
    }
}

