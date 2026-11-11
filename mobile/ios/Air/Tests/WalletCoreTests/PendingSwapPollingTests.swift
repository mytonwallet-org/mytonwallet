import Foundation
import Testing
@testable import WalletCore

@Suite("Pending swap polling")
struct PendingSwapPollingTests {
    @Test
    func `backend cross-chain swaps are polled besides CEX ones`() throws {
        let swap = try makeSwap(to: "arbitrum-0xaf88d065e77c8cc2239327c5edb3a432268e5831")
        #expect(getIsCrossChainBackendSwap("vt-id:backend-swap", swap))
    }

    @Test
    func `same-chain and local swaps are not polled`() throws {
        #expect(!getIsCrossChainBackendSwap("dex-id:backend-swap", try makeSwap(to: "base-0xfde4c96c8593536e31f229ea8f37b2ada2699bb2")))
        #expect(!getIsCrossChainBackendSwap("vt-id:local", try makeSwap(to: "arbitrum-0xaf88d065e77c8cc2239327c5edb3a432268e5831")))
    }

    private func makeSwap(to: String) throws -> ApiSwapActivity {
        let payload: [String: Any] = [
            "kind": "swap", "id": "vt-id:backend-swap", "timestamp": 1,
            "from": "base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", "fromAmount": "1", "to": to, "toAmount": "1",
            "transactionIds": [:], "status": "pendingTrusted",
        ]
        return try JSONDecoder().decode(ApiSwapActivity.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
