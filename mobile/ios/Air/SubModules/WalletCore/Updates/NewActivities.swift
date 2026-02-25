
import WalletContext

extension ApiUpdate {
    public struct NewActivities: Equatable, Hashable, Sendable, Codable {
        public var type = "newActivities"
        public var accountId: String
        public var chain: ApiChain?
        public var activities: [ApiActivity]
        /**
           * The UI must replace all the pending activities in the given chain with the given activities. This is except to
           * local activities, but if a pending activity matchers a local activity, it replaces that local activity.
           *
           * Omitted if the update does not change the list of pending actions (the UI should keep the old list).
           *
           * Doesn't contain activities with the hashes of the current or past confirmed activities.
           *
           * There is no separate update for pending activities, because confirmed activities replace pending activities, so the
           * UI should handle both changes in one update.
           */
        public var  pendingActivities: [ApiActivity]?

        public init(accountId: String, chain: ApiChain?, activities: [ApiActivity], pendingActivities: [ApiActivity]?) {
            self.accountId = accountId
            self.chain = chain
            self.activities = activities
            self.pendingActivities = pendingActivities
        }
    }
}
