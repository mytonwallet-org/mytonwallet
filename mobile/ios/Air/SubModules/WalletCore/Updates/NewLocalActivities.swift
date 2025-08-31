
import WalletContext

extension ApiUpdate {
    public struct NewLocalActivities: Equatable, Hashable, Sendable, Codable {
        public var type = "newLocalActivities"
        public var accountId: String
        public var activities: [ApiActivity]
    }
}
