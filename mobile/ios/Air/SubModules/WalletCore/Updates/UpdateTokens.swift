
import WalletContext

extension ApiUpdate {
    public struct UpdateTokens: Equatable, Hashable, Codable, Sendable {
        public var type = "updateTokens"
        public var tokens: [String: ApiToken]
        public var baseCurrency: MBaseCurrency
        
        public init(tokens: [String : ApiToken], baseCurrency: MBaseCurrency) {
            self.tokens = tokens
            self.baseCurrency = baseCurrency
        }
    }
}
