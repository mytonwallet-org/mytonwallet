
public struct SavedAddress: Equatable, Hashable, Codable, Sendable {
    public var name: String
    public var address: String
    public var chain: ApiChain
    
    public init(name: String, address: String, chain: ApiChain) {
        self.name = name
        self.address = address
        self.chain = chain
    }
}

extension SavedAddress {
    func matches(_ other: SavedAddress) -> Bool {
        matches(chain: other.chain, address: other.address)
    }
    
    func matches(chain: ApiChain, address: String) -> Bool {
        self.chain == chain && self.address == address
    }
}
