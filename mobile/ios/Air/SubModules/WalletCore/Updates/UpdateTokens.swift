
import WalletContext
import WalletCoreTypes

extension ApiUpdate {
    public struct UpdateTokens: Equatable, Hashable, Codable, Sendable {
        public var type = "updateTokens"
        public var tokens: [String: ApiToken]
    }
}
