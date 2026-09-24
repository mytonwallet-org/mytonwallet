import Dependencies
import Foundation
import GRDB
import XCTest
import WalletCoreTypes
@testable import WalletCore

@MainActor
final class ActivityListIdentityTests: XCTestCase {
    func testCachedRepeatedIDsAreRepairedBeforeHomeAndTokenInitialization() async throws {
        for isToken in [false, true] {
            try await checkCachedRepeatedIDs(isToken: isToken)
        }
    }

    private func checkCachedRepeatedIDs(isToken: Bool) async throws {
        let first = try activity("first", day: 3)
        let second = try activity("second", day: 2)
        let state = _ActivityStore.AccountState(
            accountId: UUID().uuidString + "-mainnet",
            byId: [first.id: first, second.id: second],
            idsMain: [first.id, first.id, second.id, first.id],
            idsBySlug: ["toncoin": [first.id, first.id, second.id, second.id]],
            isMainHistoryEndReached: true,
            isHistoryEndReachedBySlug: ["toncoin": true]
        )
        let (store, db) = try await makeStore(state)
        let delegate = Delegate()
        let model = await makeModel(accountId: state.accountId, isToken: isToken, delegate: delegate, store: store, db: db)

        XCTAssertEqual(transactionIDs(model), [first.id, second.id])
        XCTAssertEqual(model.activity(forStableId: first.id), first)
        XCTAssertEqual(delegate.changes, 0)
        let saved = try await db.read { db in
            try _ActivityStore.AccountState.fetchOne(db, key: state.accountId)
        }
        XCTAssertEqual(saved?.idsMain, [first.id, second.id])
        XCTAssertEqual(saved?.idsBySlug?["toncoin"], [first.id, second.id])
    }

    func testSDKReplacementsPreserveIdentityDateAndDistinctReappearingRecords() async throws {
        for isToken in [false, true] {
            try await checkSDKReplacements(isToken: isToken)
        }
    }

    private func checkSDKReplacements(isToken: Bool) async throws {
        let accountId = UUID().uuidString + "-mainnet"
        let (store, db) = try await makeStore(.init(accountId: accountId))
        let local = try activity("transfer:local", day: 2, status: "pending")
        let other = try activity("distinct", day: 1)
        await store.addInitialActivities(accountId: accountId, mainActivities: [local, other], bySlug: ["toncoin": [local, other]])
        let delegate = Delegate()
        let model = await makeModel(accountId: accountId, isToken: isToken, delegate: delegate, store: store, db: db)

        let confirmed = try activity("confirmed", day: 3)
        let patch = ApiActivitiesPatch(accountId: accountId, upsert: [confirmed, confirmed], removeIds: [local.id], replacedIds: [local.id: confirmed.id])
        let updated = await store.applyActivitiesPatch(accountId: accountId, patch: patch, visibleChain: .ton)
        await model.handleEvent(.activitiesChanged(accountId: accountId, updatedIds: updated, replacedIds: patch.replacedIds ?? [:]))

        XCTAssertEqual(transactionIDs(model), [local.id, other.id])
        XCTAssertEqual(model.activity(forStableId: local.id), confirmed)
        XCTAssertTrue(model.snapshot.reconfiguredItemIdentifiers.contains(.transaction(accountId, local.id)))
        XCTAssertEqual(model.snapshot.sectionIdentifier(containingItem: .transaction(accountId, local.id)),
                       .transactions(accountId, Calendar.current.startOfDay(for: confirmed.timestampDate)))

        // Repeated SDK notifications must neither duplicate the row nor lose its stable identity.
        await model.handleEvent(.activitiesChanged(accountId: accountId, updatedIds: [confirmed.id, confirmed.id], replacedIds: patch.replacedIds ?? [:]))
        XCTAssertEqual(transactionIDs(model), [local.id, other.id])
        XCTAssertEqual(delegate.changes, 2)

        // A later update can reintroduce the source ID. Preserve both current records.
        await store.addInitialActivities(accountId: accountId, mainActivities: [local, confirmed, other], bySlug: ["toncoin": [local, confirmed, other]])
        await model.handleEvent(.activitiesChanged(accountId: accountId, updatedIds: [local.id], replacedIds: [:]))
        XCTAssertEqual(Set(transactionIDs(model)), Set([local.id, confirmed.id, other.id]))
        XCTAssertEqual(model.activity(forStableId: local.id), local)
        XCTAssertEqual(model.activity(forStableId: confirmed.id), confirmed)
    }

    func testInitialSDKTokenSlicesDeduplicateIDsAndRetainUpdates() async throws {
        let accountId = UUID().uuidString + "-mainnet"
        let (store, _) = try await makeStore(.init(accountId: accountId))
        let original = try activity("same", day: 1)
        let updated = try activity("same", day: 2)
        let distinct = try activity("distinct", day: 1)
        await store.addInitialActivities(accountId: accountId, mainActivities: [original, distinct], bySlug: ["toncoin": [original, original, distinct]])
        await store.addInitialActivities(accountId: accountId, mainActivities: [updated, distinct], bySlug: ["toncoin": [updated, updated, distinct]])
        let state = await store.getAccountState(accountId)
        XCTAssertEqual(state.idsMain?.count, 2)
        XCTAssertEqual(state.idsBySlug?["toncoin"]?.count, 2)
        XCTAssertEqual(state.byId?[updated.id], updated)
    }

    private func makeModel(accountId: String, isToken: Bool, delegate: Delegate, store: _ActivityStore, db: DatabaseQueue) async -> ActivityListViewModel {
        await withDependencies {
            $0.context = .test
            $0.accountStore = _AccountStore(db: db)
        } operation: {
            await ActivityListViewModel(accountId: accountId, token: isToken ? token : nil,
                                        delegate: delegate, activitiesStore: store)
        }
    }

    private var token: ApiToken {
        ApiToken(slug: "toncoin", name: "Toncoin", symbol: "TON", decimals: 9, chain: .ton)
    }

    private func transactionIDs(_ model: ActivityListViewModel) -> [String] {
        model.snapshot.itemIdentifiers.compactMap {
            if case .transaction(_, let id) = $0.value { id } else { nil }
        }
    }

    private func makeStore(_ state: _ActivityStore.AccountState) async throws -> (_ActivityStore, DatabaseQueue) {
        let db = try DatabaseQueue()
        try makeMigrator().migrate(db)
        try await db.write { db in
            try MAccount(id: state.accountId, title: "Identity test", type: .view, byChain: ["ton": AccountChain(address: "test")]).insert(db)
            try state.insert(db)
        }
        let store = _ActivityStore()
        await store.use(db: db)
        return (store, db)
    }

    private func activity(_ id: String, day: Int, status: String = "confirmed") throws -> ApiActivity {
        try JSONDecoder().decode(ApiActivity.self, from: Data("""
        {"kind":"transaction","id":"\(id)","timestamp":\(day * 86_400_000),
         "amount":"1000000000","fromAddress":"from","toAddress":"to","fee":"0",
         "slug":"toncoin","isIncoming":false,"status":"\(status)"}
        """.utf8))
    }
}

@MainActor
private final class Delegate: ActivityListViewModelDelegate {
    var changes = 0
    func activityViewModelChanged() { changes += 1 }
}
