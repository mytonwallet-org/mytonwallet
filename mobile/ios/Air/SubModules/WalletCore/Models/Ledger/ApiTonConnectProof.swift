
import Foundation
import WalletContext

public struct ApiTonConnectProof: Equatable, Hashable, Codable, Sendable {
    public var timestamp: Int
    public var domain: String
    public var payload: String
}
