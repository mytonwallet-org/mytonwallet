
import Foundation
import WalletContext

public struct ApiEthenaStakingState: MBaseStakingState, Equatable, Hashable, Codable, Sendable  {
    // base staking state
    public var id: String
    public var tokenSlug: String
    public var annualYield: MDouble
    public var yieldType: ApiYieldType
    public var balance: BigInt
    public var pool: String
    public var unstakeRequestAmount: BigInt?

    public var type = "ethena"
    public var tokenBalance: BigInt
    public var tsUsdeWalletAddress: String
    public var unlockTime: Int?
    public var annualYieldStandard: MDouble?
    public var annualYieldVerified: MDouble?
}
