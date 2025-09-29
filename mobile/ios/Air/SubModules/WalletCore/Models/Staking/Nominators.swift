
import Foundation
import WalletContext

public struct ApiStakingStateNominators: MBaseStakingState, Equatable, Hashable, Codable, Sendable {
    // base staking state
    public var id: String
    public var tokenSlug: String
    public var annualYield: MDouble
    public var yieldType: ApiYieldType
    public var balance: BigInt
    public var pool: String
    public var unstakeRequestAmount: BigInt?
    
    public var type = "nominators"
    public var start: Int
    public var end: Int
}
