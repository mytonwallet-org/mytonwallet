
import WalletContext

extension ApiUpdate {
    public struct UpdateStaking: Equatable, Hashable, Decodable, Sendable  {
        public var type = "updateStaking"
        public var accountId: String
        public var states: [ApiStakingState]
        public var totalProfit: BigInt
        public var shouldUseNominators: Bool?
    }
}
