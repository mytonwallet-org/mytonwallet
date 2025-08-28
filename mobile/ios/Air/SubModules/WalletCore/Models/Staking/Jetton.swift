
import Foundation
import WalletContext

public struct ApiStakingStateJetton: MBaseStakingState, Equatable, Hashable, Codable, Sendable {
    // base staking state
    public var id: String
    public var tokenSlug: String
    public var annualYield: MDouble
    public var yieldType: ApiYieldType
    public var balance: BigInt
    public var pool: String
    public var unstakeRequestAmount: BigInt?
    
    public var type = "jetton"
    public var tokenAddress: String
    public var unclaimedRewards: BigInt
    public var stakeWalletAddress: String
    public var tokenAmount: BigInt
    public var period: Int64
    public var tvl: BigInt
    public var dailyReward: BigInt
    public var poolWallets: [String]?
}
