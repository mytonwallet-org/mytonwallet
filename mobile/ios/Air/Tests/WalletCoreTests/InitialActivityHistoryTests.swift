import Testing
@testable import WalletCore

@Suite("Initial Activity History")
struct InitialActivityHistoryTests {
    @Test
    func `empty history ends only after every supported chain reports no more pages`() {
        var progress = _ActivityStore.InitialMainHistoryProgress()

        progress.record(chain: .ton, hasMore: false)

        #expect(!progress.isEndReached(supportedChains: [.ton, .solana]))

        progress.record(chain: .solana, hasMore: false)

        #expect(progress.isEndReached(supportedChains: [.ton, .solana]))
    }

    @Test
    func `failed initial load remains unknown and can recover as empty`() {
        var progress = _ActivityStore.InitialMainHistoryProgress()

        progress.record(chain: .ton, hasMore: nil)

        #expect(!progress.isEndReached(supportedChains: [.ton]))

        progress.record(chain: .ton, hasMore: false)

        #expect(progress.isEndReached(supportedChains: [.ton]))
    }

    @Test
    func `a chain with more pages keeps the main history open`() {
        var progress = _ActivityStore.InitialMainHistoryProgress()
        progress.record(chain: .ton, hasMore: false)
        progress.record(chain: .solana, hasMore: true)

        #expect(!progress.isEndReached(supportedChains: [.ton, .solana]))
    }

    @Test
    func `a chain with more pages reopens previously completed history`() {
        var progress = _ActivityStore.InitialMainHistoryProgress()
        progress.record(chain: .ton, hasMore: false)
        progress.record(chain: .solana, hasMore: false)

        #expect(progress.reconciledEndState(
            current: true,
            supportedChains: [.ton, .solana]
        ) == true)

        progress.record(chain: .solana, hasMore: true)

        #expect(progress.reconciledEndState(
            current: true,
            supportedChains: [.ton, .solana]
        ) == nil)
    }

    @Test
    func `missing chain metadata preserves a completed history`() {
        var progress = _ActivityStore.InitialMainHistoryProgress()
        progress.record(chain: .ton, hasMore: false)
        progress.record(chain: .solana, hasMore: nil)

        #expect(progress.reconciledEndState(
            current: true,
            supportedChains: [.ton, .solana]
        ) == true)
    }
}

@Suite("Activity History Load Retry")
struct ActivityHistoryLoadRetryTests {
    @Test
    func `full history retries while its end is unknown`() {
        let policy = ActivityListViewModel.LoadRetryPolicy.standard

        #expect(policy.shouldRetry(isEndReached: nil))
        #expect(policy.shouldRetry(isEndReached: false))
    }

    @Test
    func `completed history does not retry`() {
        let policy = ActivityListViewModel.LoadRetryPolicy.standard

        #expect(!policy.shouldRetry(isEndReached: true))
    }
}
