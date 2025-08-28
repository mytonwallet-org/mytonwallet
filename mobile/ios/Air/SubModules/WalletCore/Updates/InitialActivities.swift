
import WalletContext


extension ApiUpdate {
    public struct InitialActivities: Equatable, Hashable, Codable, Sendable {
        public var type = "initialActivities"
        public var accountId: String
        public var chain: ApiChain?
        public var mainActivities: [ApiActivity]
        public var bySlug: [String: [ApiActivity]]
    }
}
