import Testing
@testable import UISwap

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

}
