import Testing
@testable import WalletCore

@Suite("Activity Store Persistence")
struct ActivityStorePersistenceTests {
    @Test
    func `persistence snapshot excludes local and pending activities`() {
        let local = activity(id: "local:local", status: .pendingTrusted)
        let pending = activity(id: "pending", status: .pending)
        let confirmed = activity(id: "confirmed", status: .confirmed)
        let state = _ActivityStore.AccountState(
            accountId: "0-mainnet",
            byId: [local.id: local, pending.id: pending, confirmed.id: confirmed],
            idsMain: [local.id, pending.id, confirmed.id],
            idsBySlug: ["toncoin": [local.id, pending.id, confirmed.id]],
            newestActivitiesBySlug: ["toncoin": local],
            isMainHistoryEndReached: false,
            isHistoryEndReachedBySlug: ["toncoin": false],
            localActivityIds: [local.id],
            pendingActivityIds: ["ton": [pending.id]],
            isInitialLoadedByChain: ["ton": true]
        )

        let snapshot = state.persistenceSnapshot()

        #expect(snapshot.byId == [confirmed.id: confirmed])
        #expect(snapshot.idsMain == [confirmed.id])
        #expect(snapshot.idsBySlug == ["toncoin": [confirmed.id]])
        #expect(snapshot.localActivityIds == nil)
        #expect(snapshot.pendingActivityIds == nil)
        #expect(snapshot.newestActivitiesBySlug == ["toncoin": confirmed])
        #expect(snapshot.isInitialLoadedByChain == ["ton": true])
    }
}

private func activity(id: String, status: ApiTransactionStatus) -> ApiActivity {
    .transaction(
        ApiTransactionActivity(
            id: id,
            kind: "transaction",
            externalMsgHashNorm: nil,
            timestamp: 0,
            amount: 0,
            fromAddress: "from",
            toAddress: "to",
            comment: nil,
            encryptedComment: nil,
            fee: 0,
            slug: "toncoin",
            isIncoming: false,
            normalizedAddress: nil,
            type: nil,
            metadata: nil,
            nft: nil,
            status: status
        )
    )
}
