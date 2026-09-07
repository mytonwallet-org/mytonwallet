import Foundation
import Testing
@testable import UISwap
import WalletCore
import WalletContext

@Suite("Swap Estimate Backoff")
struct SwapEstimateBackoffTests {

    @Test
    func `the first failure retries at once and later ones double up to the ceiling`() {
        #expect(estimateTicksToWait(failedAttempts: 0) == 1)
        #expect(estimateTicksToWait(failedAttempts: 1) == 1)
        #expect(estimateTicksToWait(failedAttempts: 2) == 2)
        #expect(estimateTicksToWait(failedAttempts: 3) == 4)
        #expect(estimateTicksToWait(failedAttempts: 6) == 32)
    }

    @Test
    func `the ceiling holds however long the run of failures gets`() {
        #expect(estimateTicksToWait(failedAttempts: 64) == maxEstimateBackoffTicks)
        #expect(estimateTicksToWait(failedAttempts: 10_000) == maxEstimateBackoffTicks)
    }

    @Test
    func `a request for the inputs in flight is owed no follow up`() throws {
        var gate = SwapEstimateGate()

        let slot = gate.start(makeGateInput(sellingAmount: 100))
        let repeated = gate.start(makeGateInput(sellingAmount: 100))
        let didRequestFollowUp = gate.finish(try #require(slot))

        #expect(repeated == nil)
        #expect(!didRequestFollowUp)
    }

    @Test
    func `returning to the inputs in flight takes the follow up back`() throws {
        var gate = SwapEstimateGate()

        let slot = gate.start(makeGateInput(sellingAmount: 100))
        _ = gate.start(makeGateInput(sellingAmount: 200))
        _ = gate.start(makeGateInput(sellingAmount: 100))
        let didRequestFollowUp = gate.finish(try #require(slot))

        #expect(!didRequestFollowUp)
    }

    @Test
    func `identical inputs do not let a cancelled estimate release its successor`() throws {
        var gate = SwapEstimateGate()

        let cancelled = gate.start(makeGateInput(sellingAmount: 100))
        gate.reset()
        let running = gate.start(makeGateInput(sellingAmount: 100))
        let staleRelease = gate.finish(try #require(cancelled))
        let stillHeld = gate.isInFlight
        let properRelease = gate.finish(try #require(running))

        #expect(!staleRelease)
        #expect(stillHeld)
        #expect(!properRelease)
        #expect(!gate.isInFlight)
    }
}

private func makeGateInput(sellingAmount: BigInt) -> SwapEstimateInput {
    SwapEstimateInput(
        accountId: "test-mainnet",
        selling: TokenAmount(sellingAmount, token(slug: "toncoin", symbol: "TON", chain: .ton)),
        buying: TokenAmount(0, token(slug: "usdt", symbol: "USDT", chain: .ton)),
        inputSource: .selling,
        isMaxAmount: false,
        maxAmount: nil,
        slippage: 5
    )
}

private func token(slug: String, symbol: String, chain: ApiChain, decimals: Int = 9) -> ApiToken {
    ApiToken(
        slug: slug,
        name: symbol,
        symbol: symbol,
        decimals: decimals,
        chain: chain
    )
}
