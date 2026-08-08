import Testing
import WalletContext
import WalletCoreTypes
@testable import WalletCore

@Suite("Staking Token Presentation")
struct StakingTokenPresentationTests {
    @Test
    func `empty MY staking does not expose Earn or an accessory`() {
        let data = makeStakingData(balance: 0, unclaimedRewards: 0, annualYield: 0)
        let base = data.stakingTokenPresentation(tokenSlug: MYCOIN_SLUG, isStaking: false)

        #expect(!data.isEarnAvailable(forTokenSlug: MYCOIN_SLUG))
        #expect(!data.isEarnAvailable(forTokenSlug: STAKED_MYCOIN_SLUG))
        #expect(base?.accessory == nil)
        #expect(base?.badge == nil)
    }

    @Test
    func `empty MY staking is hidden`() {
        let data = makeStakingData(balance: 0, unclaimedRewards: 0, annualYield: 0)

        #expect(!data.hasMycoinStakeOrRewards)
    }

    @Test
    func `existing MY stake remains visible`() {
        let data = makeStakingData(balance: 1, unclaimedRewards: 0, annualYield: 0)

        #expect(data.hasMycoinStakeOrRewards)
        #expect(data.isEarnAvailable(forTokenSlug: MYCOIN_SLUG))
    }

    @Test
    func `unclaimed MY rewards remain visible`() {
        let data = makeStakingData(balance: 0, unclaimedRewards: 1, annualYield: 0)

        #expect(data.hasMycoinStakeOrRewards)
        #expect(data.isEarnAvailable(forTokenSlug: STAKED_MYCOIN_SLUG))
    }

    @Test
    func `zero APY MY position uses inactive accessory only on staking representations`() {
        let data = makeStakingData(balance: 1, unclaimedRewards: 0, annualYield: 0)

        let base = data.stakingTokenPresentation(tokenSlug: MYCOIN_SLUG, isStaking: false)
        let stakingRow = data.stakingTokenPresentation(tokenSlug: MYCOIN_SLUG, isStaking: true)
        let stakedToken = data.stakingTokenPresentation(tokenSlug: STAKED_MYCOIN_SLUG, isStaking: false)

        #expect(base?.accessory == nil)
        #expect(stakingRow?.accessory == .inactive)
        #expect(stakingRow?.badge == nil)
        #expect(stakedToken?.accessory == .inactive)
        #expect(stakedToken?.badge == nil)
    }

    @Test
    func `empty positive APY staking uses a disabled badge without an accessory on the base token`() {
        let data = makeStakingData(
            tokenSlug: TON_USDE_SLUG,
            balance: 0,
            unclaimedRewards: 0,
            annualYield: 12
        )

        let base = data.stakingTokenPresentation(tokenSlug: TON_USDE_SLUG, isStaking: false)
        let stakingRow = data.stakingTokenPresentation(tokenSlug: TON_USDE_SLUG, isStaking: true)

        #expect(base?.accessory == nil)
        #expect(base?.badge?.isActive == false)
        #expect(stakingRow?.accessory == nil)
    }

    @Test
    func `positive APY position uses active accessory on staking row and staked token`() {
        let data = makeStakingData(
            tokenSlug: TON_USDE_SLUG,
            balance: 1,
            unclaimedRewards: 0,
            annualYield: 12
        )

        let base = data.stakingTokenPresentation(tokenSlug: TON_USDE_SLUG, isStaking: false)
        let stakingRow = data.stakingTokenPresentation(tokenSlug: TON_USDE_SLUG, isStaking: true)
        let stakedToken = data.stakingTokenPresentation(tokenSlug: TON_TSUSDE_SLUG, isStaking: false)

        #expect(base?.accessory == nil)
        #expect(base?.badge == nil)
        #expect(stakingRow?.accessory == .active)
        #expect(stakingRow?.badge?.isActive == true)
        #expect(stakedToken?.accessory == .active)
        #expect(stakedToken?.badge?.isActive == true)
    }

    @Test
    func `Earn availability requires matching staking state`() {
        let data = makeStakingData(
            tokenSlug: TON_USDE_SLUG,
            balance: 0,
            unclaimedRewards: 0,
            annualYield: 12
        )

        #expect(data.isEarnAvailable(forTokenSlug: TON_USDE_SLUG))
        #expect(data.isEarnAvailable(forTokenSlug: TON_TSUSDE_SLUG))
        #expect(!data.isEarnAvailable(forTokenSlug: "unknown-token"))
    }

    private func makeStakingData(
        tokenSlug: String = MYCOIN_SLUG,
        balance: BigInt,
        unclaimedRewards: BigInt,
        annualYield: Double
    ) -> MStakingData {
        let stateId = tokenSlug == TON_USDE_SLUG ? "ethena" : MYCOIN_STAKING_POOL
        let state = ApiStakingState.jetton(ApiStakingStateJetton(
            id: stateId,
            tokenSlug: tokenSlug,
            annualYield: MDouble(annualYield),
            yieldType: .apy,
            balance: balance,
            pool: stateId,
            unstakeRequestAmount: nil,
            tokenAddress: "token-address",
            unclaimedRewards: unclaimedRewards,
            stakeWalletAddress: "stake-wallet-address",
            tokenAmount: 0,
            period: 0,
            tvl: 0,
            dailyReward: 0,
            poolWallets: nil
        ))
        return MStakingData(
            accountId: "my-staking-test",
            stateById: [stateId: state],
            totalProfit: 0,
            shouldUseNominators: nil
        )
    }
}
