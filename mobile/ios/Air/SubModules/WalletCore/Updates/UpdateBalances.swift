
import WalletContext

extension ApiUpdate {
    public struct UpdateBalances: Equatable, Hashable, Decodable, Sendable {
        public let type = "updateBalances"
        public var accountId: String
        public var chain: ApiChain
        public var balances: [String: BigInt]
        
        private enum CodingKeys: CodingKey {
            case accountId
            case chain
            case balances
        }
    }
}
