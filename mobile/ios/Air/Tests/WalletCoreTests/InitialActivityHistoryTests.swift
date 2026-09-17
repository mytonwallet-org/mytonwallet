import Foundation
import GRDB
import Testing
@testable import WalletCore

@Suite("Initial Activity History")
struct InitialActivityHistoryTests {
    @Test(arguments: [false, true])
    func `cross-chain initial updates preserve BCH history after restart`(swapArrivesFirst: Bool) async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let account = MAccount(
            id: "0-mainnet", title: "History test", type: .view,
            byChain: ["bitcoincash": AccountChain(address: "bch-test")]
        )
        let transfers = try (1...5).map { index in
            try JSONDecoder().decode(ApiActivity.self, from: Data("""
            {"kind":"transaction","id":"bch-\(index)","timestamp":\(1000 + index),
             "amount":"1","fromAddress":"from","toAddress":"to","fee":"0",
             "slug":"bch","isIncoming":false,"status":"confirmed"}
            """.utf8))
        }.reversed().map { $0 }
        let swap = try JSONDecoder().decode(ApiActivity.self, from: Data("""
        {"kind":"swap","id":"sol-bch:backend-swap","timestamp":900,
         "from":"sol","fromAmount":"0.32","to":"bch","toAmount":"0.13",
         "transactionIds":{},"status":"completed"}
        """.utf8))
        let history = transfers + [swap]
        let cached = _ActivityStore.AccountState(
            accountId: account.id,
            byId: Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) }),
            idsMain: history.map(\.id),
            idsBySlug: ["bch": history.map(\.id)],
            isHistoryEndReachedBySlug: ["bch": true]
        ).persistenceSnapshot()
        try await db.write { db in
            try account.insert(db)
            try cached.insert(db)
        }

        let store = _ActivityStore()
        await store.use(db: db)
        let updates = swapArrivesFirst ? [[swap], history] : [history, [swap]]
        for activities in updates {
            await store.addInitialActivities(
                accountId: account.id, mainActivities: activities, bySlug: ["bch": activities]
            )
        }
        let refreshed = await store.getAccountState(account.id)
        #expect(refreshed.idsBySlug?["bch"] == history.map(\.id))
        #expect(refreshed.newestActivitiesBySlug?["bch"] == transfers.first)
        // An empty initial slice must not erase already downloaded history either.
        await store.addInitialActivities(accountId: account.id, mainActivities: [], bySlug: ["bch": []])

        let state = await store.getAccountState(account.id)
        #expect(state.idsBySlug?["bch"] == history.map(\.id))
        #expect(state.newestActivitiesBySlug?["bch"] == transfers.first)
        #expect(state.isHistoryEndReachedBySlug?["bch"] == true)
        let persisted = try await db.read { db in
            try _ActivityStore.AccountState.fetchOne(db, key: account.id)
        }
        #expect(persisted?.idsBySlug?["bch"] == history.map(\.id))
        #expect(persisted?.newestActivitiesBySlug?["bch"] == transfers.first)
    }

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
