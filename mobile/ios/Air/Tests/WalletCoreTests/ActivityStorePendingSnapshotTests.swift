import Testing
@testable import WalletCore

@Suite("Activity Store Pending Snapshots")
struct ActivityStorePendingSnapshotTests {
    @Test
    func `partial newActivities patch preserves existing pending snapshot`() {
        let idsToRemove = _ActivityStore.pendingActivityIdsToReplaceForNewActivities(
            currentPendingActivityIds: [ApiChain.bitcoin.rawValue: ["btc-pending-a"]],
            chain: .bitcoin,
            pendingActivities: nil
        )

        #expect(idsToRemove.isEmpty)
    }

    @Test
    func `explicit empty pending snapshot clears existing pending snapshot`() {
        let idsToRemove = _ActivityStore.pendingActivityIdsToReplaceForNewActivities(
            currentPendingActivityIds: [ApiChain.bitcoin.rawValue: ["btc-pending-a"]],
            chain: .bitcoin,
            pendingActivities: []
        )

        #expect(idsToRemove == ["btc-pending-a"])
    }
}
