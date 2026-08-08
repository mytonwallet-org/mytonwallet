import Foundation
import Testing
@testable import UISwap
import WalletCore

@Suite("Swap Protected Action")
struct SwapProtectedActionTests {
    @Test
    func `sdk activity is matched by its exact id`() throws {
        let expected = try swapActivity(id: "expected:backend-swap")
        let result = SwapExecutionResult(activity: expected, swapId: nil, mfaRequestHash: nil)

        #expect(result.matches(activity: expected))
        #expect(!result.matches(activity: try swapActivity(id: "other:backend-swap")))
    }

    @Test
    func `submitted swap is matched through local or backend activity id`() throws {
        let result = SwapExecutionResult(activity: nil, swapId: "swap-id", mfaRequestHash: nil)

        #expect(result.matches(activity: try swapActivity(id: "swap-id::local")))
        #expect(result.matches(activity: try swapActivity(id: "swap-id::backend-swap")))
        #expect(!result.matches(activity: try swapActivity(id: "other::local")))
    }

    @Test
    func `uncorrelated result does not consume an unrelated activity`() throws {
        let result = SwapExecutionResult.submitted

        #expect(!result.matches(activity: try swapActivity(id: "swap-id::local")))
        #expect(!result.matches(activity: transactionActivity(id: "swap-id::local")))
    }

    @Test
    func `mfa receipt correlation does not suppress exact swap id matching`() throws {
        let result = SwapExecutionResult(activity: nil, swapId: "swap-id", mfaRequestHash: "mfa-request")
        let receipt = ActionSubmissionReceipt(
            payload: result,
            externalMessageHashes: ["later-transaction-hash"]
        )
        let activity = try swapActivity(id: "swap-id::backend-swap")

        #expect(SwapExecutionResult.matches(activity: activity, receipt: receipt))
    }

    private func swapActivity(id: String) throws -> ApiActivity {
        let json = """
        {
          "kind": "swap",
          "id": "\(id)",
          "timestamp": 1770000000,
          "from": "toncoin",
          "fromAmount": "1",
          "to": "tether-usdt",
          "toAmount": "2",
          "status": "pendingTrusted",
          "transactionIds": {}
        }
        """
        return try JSONDecoder().decode(ApiActivity.self, from: Data(json.utf8))
    }

    private func transactionActivity(id: String) -> ApiActivity {
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
                status: .pendingTrusted
            )
        )
    }
}
