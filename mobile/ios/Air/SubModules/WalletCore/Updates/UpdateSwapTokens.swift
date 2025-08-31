
import WalletContext

extension ApiUpdate {
    
    public struct UpdateSwapTokens: Equatable, Hashable, Codable, Sendable {
        public var type = "updateSwapTokens"
        public var tokens: [String: ApiToken]
    }
}
