
import Foundation
import WalletContext

public protocol ApiBaseWallet {
    var address: String { get }
    /// Misses in view wallets. Though, it is presented in TON view wallets that are initialized wallet contracts.
    var publicKey: String? { get }
    var index: Int { get }
}

public struct ApiTonWallet: ApiBaseWallet, Equatable, Hashable, Codable, Sendable {
    
    // ApiBaseWallet
    public var address: String
    /// Misses in view wallets. Though, it is presented in TON view wallets that are initialized wallet contracts.
    public var publicKey: String?
    public var index: Int
    
    public var version: String?
    public var isInitialized: Bool?
    public var authToken: String?
}

public struct ApiTronWallet: ApiBaseWallet, Equatable, Hashable, Codable, Sendable {
    
    // ApiBaseWallet
    public var address: String
    /// Misses in view wallets. Though, it is presented in TON view wallets that are initialized wallet contracts.
    public var publicKey: String?
    public var index: Int
}

public typealias ApiAnyChainWallet = ApiTonWallet
