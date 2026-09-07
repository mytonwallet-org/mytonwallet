import Testing
import WalletContext
import WalletCoreTypes
@testable import WalletCore

@Suite("TON Staking Position")
struct TonStakingPositionTests {
    @Test
    func `a lone liquid position answers for TON`() {
        let data = makeStakingData(liquidBalance: 0, nominators: nil, shouldUseNominators: true)

        #expect(data.tonState?.id == "liquid")
    }

    @Test
    func `a forced account with an empty liquid stake stays in nominators`() {
        let data = makeStakingData(liquidBalance: 0, nominators: 0, shouldUseNominators: true)

        #expect(data.tonState?.id == "nominators")
    }

    @Test
    func `an active nominators stake wins while liquid is empty`() {
        let data = makeStakingData(liquidBalance: 0, nominators: 10_000_000_000_000, shouldUseNominators: true)

        #expect(data.tonState?.id == "nominators")
    }

    @Test
    func `an active liquid stake wins when both are active`() {
        let data = makeStakingData(
            liquidBalance: 5_000_000_000,
            nominators: 10_000_000_000_000,
            shouldUseNominators: true
        )

        #expect(data.tonState?.id == "liquid")
    }

    @Test
    func `a liquid stake waiting to unstake still wins the tie`() {
        // A fully unstaked liquid position keeps its money in the pending request, not in the balance.
        let data = makeStakingData(
            liquidBalance: 0,
            nominators: 10_000_000_000_000,
            shouldUseNominators: true,
            liquidUnstakeRequestAmount: 5_000_000_000
        )

        #expect(data.tonState?.id == "liquid")
    }

    @Test
    func `a nominators position answers even when the flag contradicts it`() {
        // The API builds the position from a wider condition than the flag shipped beside it.
        let data = makeStakingData(liquidBalance: 0, nominators: 10_000_000_000_000, shouldUseNominators: false)

        #expect(data.tonState?.id == "nominators")
    }

    private func makeStakingData(
        liquidBalance: BigInt,
        nominators nominatorsBalance: BigInt?,
        shouldUseNominators: Bool?,
        liquidUnstakeRequestAmount: BigInt? = nil
    ) -> MStakingData {
        let liquid = ApiStakingState.liquid(ApiStakingStateLiquid(
            id: "liquid",
            tokenSlug: TONCOIN_SLUG,
            annualYield: MDouble(13.62),
            yieldType: .apy,
            balance: liquidBalance,
            pool: "liquid-pool",
            unstakeRequestAmount: liquidUnstakeRequestAmount,
            tokenBalance: liquidBalance,
            loyaltyBalance: nil,
            instantAvailable: 0,
            start: 0,
            end: 0,
            totalStakers: 0,
            tvl: 0
        ))
        var stateById: [String: ApiStakingState] = ["liquid": liquid]

        if let nominatorsBalance {
            stateById["nominators"] = .nominators(ApiStakingStateNominators(
                id: "nominators",
                tokenSlug: TONCOIN_SLUG,
                annualYield: MDouble(9.58),
                yieldType: .apy,
                balance: nominatorsBalance,
                pool: "nominators-pool",
                unstakeRequestAmount: nil,
                start: 0,
                end: 0
            ))
        }

        return MStakingData(
            accountId: "ton-staking-test",
            stateById: stateById,
            totalProfit: 0,
            shouldUseNominators: shouldUseNominators
        )
    }
}
