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
    func `burn hides implementation address everywhere`() {
        let activity = makeActivity(type: .burn, slug: TONCOIN_SLUG)

        #expect(!activity.shouldShowTransactionAddress(in: .list))
        #expect(!activity.shouldShowTransactionAddress(in: .details))
    }

    @Test
    func `zero approval keeps its allowance visible`() {
        let activity = makeActivity(type: .approval, amount: BigInt(0))

        #expect(activity.amountDisplayMode == .approval)
        #expect(activity.shouldShowTransactionAddress(in: .list))
        #expect(activity.shouldShowTransactionAddress(in: .details))
    }

    private func makeActivity(
        type: ApiTransactionType?,
        slug: String = TONCOIN_SLUG,
        amount: BigInt = BigInt(1)
    ) -> ApiActivity {
        .transaction(.init(
            id: "transaction-address-display-\(type?.rawValue ?? "transfer")-\(slug)",
            kind: "transaction",
            externalMsgHashNorm: nil,
            timestamp: 0,
            amount: amount,
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
