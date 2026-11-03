import Testing
import WalletCore
@testable import UIAssets

@Suite @MainActor
struct PerpsHomeStateTests {
    private func fixture(account: String = "wallet-a") -> PerpsHomeDisplayData {
        .init(positions: .init(accountID: account, totalValue: .fromDouble(130, .USD), profitLoss: .init("+$30", tone: .positive),
                              positions: [.init(id: "btc", token: .TONCOIN, directionAndLeverage: "Long 5x", value: "$130", profitLoss: .init("+$30"))]),
              marketSections: [.init(id: "popular", title: "Popular", layout: .grid,
                                     tokens: [.init(id: "ton", token: .TONCOIN, change: "+1%", isPositive: true)], showsSeeAll: true)],
              activities: [.init(id: "closed", kind: .closed, title: "Closed", badge: "5x Long", date: "Today", amount: .init("+$130"))])
    }

    @Test func `late responses from another wallet never replace positions or history`() {
        let state = PerpsHomeState(data: fixture()) { _ in }
        var other = fixture(account: "wallet-b")
        other.positions.positions = []
        other.activities = []
        state.update(other)
        #expect(state.data.positions.accountID == "wallet-a")
        #expect(state.data.positions.positions.map(\.id) == ["btc"])
        #expect(state.data.activities.map(\.id) == ["closed"])
    }

    @Test func `stale row and activity actions cannot open removed items`() {
        var actions: [PerpsHomeAction] = []
        let state = PerpsHomeState(data: fixture()) { actions.append($0) }
        state.send(.position("btc"))
        state.send(.activity("closed"))
        var update = fixture()
        update.positions.positions = []
        update.positions.totalCount = 0
        update.activities = []
        state.update(update)
        state.send(.position("btc"))
        state.send(.activity("closed"))
        state.send(.allPositions)
        #expect(actions == [.position("btc"), .activity("closed")])
    }

    @Test func `loading and unavailable positions cannot be selected but can retry`() {
        var data = fixture()
        var actions: [PerpsHomeAction] = []
        let state = PerpsHomeState(data: data) { actions.append($0) }
        for status: PerpsPositionsDisplayData.Status in [.loading, .unavailable("Offline")] {
            data.positions.status = status
            state.update(data)
            state.send(.position("btc"))
            state.send(.allPositions)
        }
        state.send(.refresh)
        #expect(actions == [.refresh])
    }

    @Test func `snapshots normalize duplicate identities without changing adapter order`() {
        var data = fixture()
        data.positions.positions += data.positions.positions
        data.marketSections[0].tokens += data.marketSections[0].tokens
        data.marketSections += data.marketSections
        data.activities += data.activities
        let state = PerpsHomeState(data: data) { _ in }
        #expect(state.data.positions.positions.count == 1)
        #expect(state.data.marketSections.count == 1)
        #expect(state.data.marketSections[0].tokens.count == 1)
        #expect(state.data.activities.count == 1)
    }

    @Test func `market actions preserve section identity and reject stale items`() {
        var actions: [PerpsHomeAction] = []
        let state = PerpsHomeState(data: fixture()) { actions.append($0) }
        state.send(.marketToken(sectionID: "other", tokenID: "ton"))
        state.send(.marketToken(sectionID: "popular", tokenID: "gone"))
        state.send(.marketSection("other"))
        state.send(.marketToken(sectionID: "popular", tokenID: "ton"))
        #expect(actions == [.marketToken(sectionID: "popular", tokenID: "ton")])
    }
}
