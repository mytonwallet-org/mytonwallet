import Testing
import WalletCore
import WalletContext

@Suite("Transaction Address Display")
struct TransactionAddressDisplayTests {
    @Test
    func `plain transfer shows address in list and details`() {
        let activity = makeActivity(type: nil)

        #expect(activity.shouldShowTransactionAddress(in: .list))
        #expect(activity.shouldShowTransactionAddress(in: .details))
    }

    @Test
    func `ton burn shows address only in details`() {
        let activity = makeActivity(type: .burn, slug: TONCOIN_SLUG)

        #expect(!activity.shouldShowTransactionAddress(in: .list))
        #expect(activity.shouldShowTransactionAddress(in: .details))
    }

    @Test
    func `non ton burn hides address everywhere`() {
        let activity = makeActivity(type: .burn, slug: ETH_SLUG)

        #expect(!activity.shouldShowTransactionAddress(in: .list))
        #expect(!activity.shouldShowTransactionAddress(in: .details))
    }

    private func makeActivity(
        type: ApiTransactionType?,
        slug: String = TONCOIN_SLUG
    ) -> ApiActivity {
        .transaction(.init(
            id: "transaction-address-display-\(type?.rawValue ?? "transfer")-\(slug)",
            kind: "transaction",
            externalMsgHashNorm: nil,
            timestamp: 0,
            amount: BigInt(1),
            fromAddress: "from-address",
            toAddress: "to-address",
            comment: nil,
            encryptedComment: nil,
            fee: BigInt(0),
            slug: slug,
            isIncoming: false,
            normalizedAddress: nil,
            type: type,
            metadata: nil,
            nft: nil,
            status: .confirmed
        ))
    }
}
