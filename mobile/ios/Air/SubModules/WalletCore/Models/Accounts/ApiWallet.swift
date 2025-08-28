
import Foundation
import BigIntLib

public protocol ApiBaseWallet {
    var address: String { get }
    var publicKey: String { get }
    var index: Int { get }
}

public struct ApiTonWallet: ApiBaseWallet, Equatable, Hashable, Codable, Sendable {
    
    public var address: String
    public var publicKey: String
    public var index: Int
    
    public var type = "ton"
    public var version: String?
    public var isInitialized: Bool?
    public var authToken: String?
    public var lastTxId: String?
    
    public init(address: String, publicKey: String, index: Int, type: String = "ton", version: String? = nil, isInitialized: Bool? = nil, authToken: String? = nil, lastTxId: String? = nil) {
        self.address = address
        self.publicKey = publicKey
        self.index = index
        self.type = type
        self.version = version
        self.isInitialized = isInitialized
        self.authToken = authToken
        self.lastTxId = lastTxId
    }
}

public struct ApiTronWallet: ApiBaseWallet, Equatable, Hashable, Codable, Sendable {
    
    public var address: String
    public var publicKey: String
    public var index: Int
    
    public var type = "tron"
    
    public init(address: String, publicKey: String, index: Int, type: String = "tron") {
        self.address = address
        self.publicKey = publicKey
        self.index = index
        self.type = type
    }
}
