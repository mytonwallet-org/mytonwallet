import Dependencies
import Foundation
import GRDB
import Testing
@testable import WalletCore

@MainActor
@Suite("Activity List Background Pagination", .serialized)
struct ActivityListBackgroundPaginationTests {
    enum Outcome: CaseIterable, Sendable {
        case visibleHistory, endOfHistory, failure, noProgress
    }

    @Test(arguments: Outcome.allCases)
    func `filtered pages continue without visible rows and stop appropriately`(outcome: Outcome) async throws {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        let accountId = UUID().uuidString + "-mainnet"
        try await db.write { db in
            try MAccount(id: accountId, title: "Pagination test", type: .view,
                         byChain: ["ton": AccountChain(address: "test")]).insert(db)
            try _ActivityStore.AccountState(accountId: accountId, byId: [:], idsMain: [],
                idsBySlug: ["toncoin": []], isHistoryEndReachedBySlug: ["toncoin": false]).insert(db)
        }
        let pages = Pages(outcome: outcome)
        let store = _ActivityStore { _, limit, slug, cursor in
            #expect(limit == 60)
            #expect(slug == "toncoin")
            return try await pages.fetch(cursor: cursor)
        }
        await store.use(db: db)
        let delegate = Delegate()
        let model = await withDependencies {
            $0.context = .test
            $0.accountStore = _AccountStore(db: db)
        } operation: {
            await ActivityListViewModel(accountId: accountId, token: .TONCOIN,
                                        delegate: delegate, activitiesStore: store)
        }

        // No collection view or loading row ever requests another page.
        await model.requestMoreIfNeeded()
        for _ in 0..<200 {
            if await model.loadMoreTask == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await model.loadMoreTask == nil)
        #expect(await pages.cursors.count == 4)
        let cursors = await pages.cursors
        #expect(cursors.first == .some(nil))
        #expect(cursors.dropFirst().allSatisfy { $0 != nil })
        let timestamps = cursors.compactMap { $0 }
        if outcome != .noProgress {
            #expect(zip(timestamps, timestamps.dropFirst()).allSatisfy { $0 > $1 })
        }

        let transactions = model.snapshot.itemIdentifiers.filter {
            if case .transaction = $0.value { return true }
            return false
        }
        switch outcome {
        case .visibleHistory:
            #expect(transactions.count == 60)
            #expect(model.isEndReached != true)
            #expect(!model.hasLoadError)
        case .endOfHistory:
            #expect(transactions.isEmpty)
            #expect(model.isEndReached == true)
            #expect(!model.hasLoadError)
            await model.requestMoreIfNeeded()
        case .failure:
            #expect(transactions.isEmpty)
            #expect(model.isEndReached != true)
            #expect(model.hasLoadError)
        case .noProgress:
            #expect(transactions.isEmpty)
            #expect(model.isEndReached != true)
            #expect(!model.hasLoadError)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(await pages.cursors.count == 4)
    }

    private actor Pages {
        let outcome: Outcome
        var cursors: [Int64?] = []

        init(outcome: Outcome) { self.outcome = outcome }

        func fetch(cursor: Int64?) throws -> ApiActivitySliceResult {
            cursors.append(cursor)
            let page = cursors.count
            guard page <= 4 else { throw URLError(.badServerResponse) }
            if page == 4 {
                switch outcome {
                case .endOfHistory: return ApiActivitySliceResult(activities: [], hasMore: false)
                case .failure: throw URLError(.notConnectedToInternet)
                case .visibleHistory, .noProgress: break
                }
            }
            let activities = try (0..<60).map { index in
                let pageIndex = outcome == .noProgress ? (page - 1) % 2 : page - 1
                let number = pageIndex * 60 + index
                return try JSONDecoder().decode(ApiActivity.self, from: Data("""
                {"kind":"transaction","id":"tx-\(number)","timestamp":\(30_000_000 - number * 1000),
                 "amount":"-1000000000","fromAddress":"from","toAddress":"to","fee":"0",
                 "slug":"toncoin","isIncoming":false,"status":"confirmed","shouldHide":\(page < 4 || outcome == .noProgress)}
                """.utf8))
            }
            return ApiActivitySliceResult(activities: activities, hasMore: true)
        }
    }

    private final class Delegate: ActivityListViewModelDelegate {
        func activityViewModelChanged() {}
    }
}
