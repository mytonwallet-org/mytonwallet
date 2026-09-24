import Foundation
import OrderedCollections
import Testing
@testable import WalletCore

@Suite("Activity List Snapshot")
struct ActivityListSnapshotProxyTests {
    @Test
    func `repeated identifiers within and across dates appear once without empty sections`() {
        let proxy = ActivityListSnapshotProxy(accountId: "0-mainnet", customSectionIDs: ["tokens"])
        let dates = (1...3).map { Date(timeIntervalSince1970: Double($0) * 86_400) }
        let snapshot = proxy.makeSnapshot(
            idsByDate: [dates[2]: ["a", "a", "b"], dates[1]: ["b", "c"], dates[0]: ["a", "c"]],
            isEndReached: false,
            updatedIds: ["a", "c", "c", "missing"]
        )

        #expect(snapshot.itemIdentifiers == [
            .headerPlaceholder, .custom("tokens"),
            .transaction("0-mainnet", "a"), .transaction("0-mainnet", "b"),
            .transaction("0-mainnet", "c"), .loadingMore,
        ])
        #expect(!snapshot.sectionIdentifiers.contains(.transactions("0-mainnet", dates[0])))
        #expect(snapshot.itemIdentifiers(inSection: .transactions("0-mainnet", dates[1])) == [
            .transaction("0-mainnet", "c"), .loadingMore,
        ])
        #expect(snapshot.reconfiguredItemIdentifiers == [.transaction("0-mainnet", "a"), .transaction("0-mainnet", "c")])
    }

    @Test
    func `pagination counts unique rows when the final identifiers repeat`() {
        var proxy = ActivityListSnapshotProxy(accountId: "0-mainnet", customSectionIDs: [], remoteLoadThreshold: 2)
        let date = Date(timeIntervalSince1970: 86_400)
        proxy.didUpdateData(idsByDate: [date: ["a", "b", "c", "d", "d", "d"]])

        #expect(!proxy.rowDidBecomeVisible(.transaction("0-mainnet", "b"), isEndReached: false))
        #expect(proxy.rowDidBecomeVisible(.transaction("0-mainnet", "c"), isEndReached: false))
        #expect(proxy.rowDidBecomeVisible(.transaction("0-mainnet", "d"), isEndReached: false))
    }

    @Test(arguments: [false, true])
    func `empty date buckets use the appropriate placeholder`(isEndReached: Bool) {
        let proxy = ActivityListSnapshotProxy(accountId: "0-mainnet", customSectionIDs: [])
        let snapshot = proxy.makeSnapshot(idsByDate: [Date(): []], isEndReached: isEndReached, updatedIds: [])
        #expect(snapshot.itemIdentifiers == [.headerPlaceholder, isEndReached ? .emptyPlaceholder : .loadingMore])
    }

    @Test
    func `unknown history uses skeletons and known empty history uses empty state`() {
        var proxy = ActivityListSnapshotProxy(accountId: "0-mainnet", customSectionIDs: [])

        proxy.didUpdateData(idsByDate: nil)
        let loadingSnapshot = proxy.makeSnapshot(idsByDate: nil, isEndReached: nil, updatedIds: [])

        #expect(loadingSnapshot.sectionIdentifiers.contains(.placeholderTransactionsSection))
        #expect(loadingSnapshot.itemIdentifiers.contains { row in
            if case .transactionPlaceholder = row.value { true } else { false }
        })
        #expect(!loadingSnapshot.sectionIdentifiers.contains(.emptyPlaceholder))

        proxy.didUpdateData(idsByDate: [:])
        let emptySnapshot = proxy.makeSnapshot(idsByDate: [:], isEndReached: true, updatedIds: [])

        #expect(!emptySnapshot.sectionIdentifiers.contains(.placeholderTransactionsSection))
        #expect(emptySnapshot.sectionIdentifiers.contains(.emptyPlaceholder))
        #expect(emptySnapshot.itemIdentifiers.contains(.emptyPlaceholder))
        #expect(!emptySnapshot.itemIdentifiers.contains(.loadingMore))
        #expect(!emptySnapshot.itemIdentifiers.contains { row in
            if case .transactionPlaceholder = row.value { true } else { false }
        })
    }

    @Test
    func `empty filtered history keeps loading until history end is known`() {
        for isEndReached in [nil, false] as [Bool?] {
            var proxy = ActivityListSnapshotProxy(accountId: "0-mainnet", customSectionIDs: [])
            proxy.didUpdateData(idsByDate: [:])

            let snapshot = proxy.makeSnapshot(idsByDate: [:], isEndReached: isEndReached, updatedIds: [])

            #expect(!snapshot.sectionIdentifiers.contains(.emptyPlaceholder))
            #expect(!snapshot.itemIdentifiers.contains(.emptyPlaceholder))
            #expect(snapshot.itemIdentifiers.contains(.loadingMore))

            #expect(proxy.rowDidBecomeVisible(.loadingMore, isEndReached: isEndReached))
        }
    }

    @Test
    func `snapshot includes every locally loaded activity`() {
        var proxy = ActivityListSnapshotProxy(accountId: "0-mainnet", customSectionIDs: [])
        let date = Date(timeIntervalSince1970: 1_000_000)
        let ids = (0..<35).map { "activity-\($0)" }
        let idsByDate: OrderedDictionary<Date, [String]> = [date: ids]

        proxy.didUpdateData(idsByDate: idsByDate)
        let snapshot = proxy.makeSnapshot(idsByDate: idsByDate, isEndReached: false, updatedIds: [])
        let snapshotActivityIds = snapshot.itemIdentifiers.compactMap { row -> String? in
            if case .transaction(_, let id) = row.value { id } else { nil }
        }

        #expect(snapshotActivityIds == ids)
        #expect(snapshot.itemIdentifiers.contains(.loadingMore))
    }

    @Test
    func `initially short visible list requests another remote page`() {
        var proxy = ActivityListSnapshotProxy(accountId: "0-mainnet", customSectionIDs: [])
        let date = Date(timeIntervalSince1970: 1_000_000)
        let ids = ["first", "second", "third"]
        let idsByDate: OrderedDictionary<Date, [String]> = [date: ids]

        proxy.didUpdateData(idsByDate: idsByDate)

        #expect(proxy.rowDidBecomeVisible(.transaction("0-mainnet", "first"), isEndReached: false))
        #expect(!proxy.rowDidBecomeVisible(.transaction("0-mainnet", "first"), isEndReached: true))
    }

    @Test
    func `long list requests another remote page only near its loaded end`() {
        var proxy = ActivityListSnapshotProxy(accountId: "0-mainnet", customSectionIDs: [])
        let date = Date(timeIntervalSince1970: 1_000_000)
        let ids = (0..<35).map { "activity-\($0)" }
        let idsByDate: OrderedDictionary<Date, [String]> = [date: ids]

        proxy.didUpdateData(idsByDate: idsByDate)

        #expect(!proxy.rowDidBecomeVisible(.transaction("0-mainnet", "activity-14"), isEndReached: false))
        #expect(proxy.rowDidBecomeVisible(.transaction("0-mainnet", "activity-15"), isEndReached: false))
    }
}
