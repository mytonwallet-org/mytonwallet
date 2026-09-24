import Foundation
import Testing
@testable import WalletCore

@Suite("Swap Transaction IDs")
struct SwapTransactionIdsTests {
    @Test
    func `completed TON summary exposes its submitted hash without changing the payload`() throws {
        let hash = "KqYMr6nBhp8phoavlGBOtwVWuBdFIDKsDGpNNdS1Ycw="
        let swap = try makeSwap(["hashes": [hash]])

        #expect(swap.displayTransactionIds.outgoing?.hash == hash)
        #expect(swap.displayTransactionIds.outgoing?.chain == .ton)
        #expect(swap.transactionIds == .init())
    }

    @Test
    func `normalized message hash takes precedence for onchain swaps`() throws {
        let swap = try makeSwap(["externalMsgHashNorm": "normalized-hash", "hashes": ["submitted-hash"]])

        #expect(swap.displayTransactionIds.outgoing?.hash == "normalized-hash")
    }

    @Test(arguments: ["2551567::backend-swap", "2551567::local"])
    func `summary IDs without hashes do not become transaction links`(id: String) throws {
        let swap = try makeSwap(["id": id])

        #expect(swap.displayTransactionIds == .init())
    }

    @Test
    func `raw swap action can use its trace ID`() throws {
        let swap = try makeSwap(["id": "trace-hash:102309952000025-action-id"])

        #expect(swap.displayTransactionIds.outgoing?.hash == "trace-hash")
    }

    @Test
    func `incoming structured reference retains its chain instead of using a source fallback`() throws {
        let swap = try makeSwap([
            "transactionIds": ["incoming": ["hash": "payout-hash", "chain": "solana"]],
            "hashes": ["source-hash"],
        ])

        #expect(swap.displayTransactionIds == swap.transactionIds)
        #expect(swap.displayTransactionIds.outgoing == nil)
        #expect(swap.displayTransactionIds.incoming?.chain == .solana)
    }

    @Test
    func `legacy CEX swap uses the source hash`() throws {
        let swap = try makeSwap([
            "externalMsgHashNorm": "message-hash",
            "hashes": ["deposit-hash"],
            "cex": ["payinAddress": "in", "payoutAddress": "out", "status": "finished", "transactionId": "provider-id"],
        ])

        #expect(swap.displayTransactionIds.outgoing?.hash == "deposit-hash")
    }

    private func makeSwap(_ overrides: [String: Any]) throws -> ApiSwapActivity {
        let payload: [String: Any] = [
            "kind": "swap", "id": "2551567::backend-swap", "timestamp": 1788942256279,
            "from": "toncoin", "fromAmount": "1", "to": "toncoin", "toAmount": "1",
            "transactionIds": [:], "status": "completed",
        ].merging(overrides) { _, new in new }
        return try JSONDecoder().decode(ApiSwapActivity.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
