import Testing
@testable import UISend
import WalletCore
import WalletContext

@Suite("Send Protected Action")
struct SendProtectedActionTests {
    @Test
    func `outgoing activity is matched using its signed amount`() {
        let activity = transactionActivity(amount: -10)

        #expect(
            ConfirmedTokenSend.matchesCommittedActivity(
                activity,
                amount: 10,
                tokenSlug: TONCOIN_SLUG,
                resolvedAddress: "destination",
                fromAddress: "sender",
                comment: "memo"
            )
        )
    }

    @Test
    func `positive activity amount is not accepted as an outgoing send`() {
        let activity = transactionActivity(amount: 10)

        #expect(
            !ConfirmedTokenSend.matchesCommittedActivity(
                activity,
                amount: 10,
                tokenSlug: TONCOIN_SLUG,
                resolvedAddress: "destination",
                fromAddress: "sender",
                comment: "memo"
            )
        )
    }

    private func transactionActivity(amount: BigInt) -> ApiActivity {
        .transaction(
            ApiTransactionActivity(
                id: "activity",
                kind: "transaction",
                externalMsgHashNorm: nil,
                timestamp: 0,
                amount: amount,
                fromAddress: "sender",
                toAddress: "destination",
                comment: "memo",
                encryptedComment: nil,
                fee: 0,
                slug: TONCOIN_SLUG,
                isIncoming: false,
                normalizedAddress: nil,
                type: nil,
                metadata: nil,
                nft: nil,
                status: .pendingTrusted
            )
        )
    }
}
