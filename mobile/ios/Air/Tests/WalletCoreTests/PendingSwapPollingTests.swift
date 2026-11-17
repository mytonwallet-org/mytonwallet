import Foundation
import Testing
@testable import WalletCore

@Suite("Pending swap polling")
struct PendingSwapPollingTests {
    @Test(arguments: [ApiSwapStatus.pending, .pendingTrusted])
    func `pending backend swaps are polled on both the same and different chains`(status: ApiSwapStatus) throws {
        let crossChain = try makeSwap(to: "arbitrum-0xaf88d065e77c8cc2239327c5edb3a432268e5831", status: status)
        let sameChain = try makeSwap(to: "base-0xfde4c96c8593536e31f229ea8f37b2ada2699bb2", status: status)
        #expect(getShouldPollSwap(.swap(crossChain)))
        #expect(getShouldPollSwap(.swap(sameChain)))
    }

    @Test
    func `local and chain swap actions are not polled`() throws {
        let local = try makeSwap(id: "swap::local", to: "arbitrum")
        let chainAction = try makeSwap(id: "chain-action", to: "arbitrum")
        #expect(!getShouldPollSwap(.swap(local)))
        #expect(!getShouldPollSwap(.swap(chainAction)))
    }

    @Test(arguments: [ApiSwapStatus.completed, .failed, .expired, .confirmed])
    func `settled backend swaps leave the polling set`(status: ApiSwapStatus) throws {
        let swap = try makeSwap(to: "arbitrum", status: status)
        #expect(!getShouldPollSwap(.swap(swap)))
    }

    @Test
    func `pending CEX swaps without a backend suffix remain polled`() throws {
        var swap = try makeSwap(id: "cex-id", to: "arbitrum")
        swap.cex = try JSONDecoder().decode(ApiSwapCexTransactionExtras.self, from: Data("""
        {"payinAddress":"deposit","payoutAddress":"destination","transactionId":"provider","status":"waiting"}
        """.utf8))
        #expect(getShouldPollSwap(.swap(swap)))
    }

    private func makeSwap(
        id: String = "swap::backend-swap",
        to: String,
        status: ApiSwapStatus = .pendingTrusted
    ) throws -> ApiSwapActivity {
        let payload: [String: Any] = [
            "kind": "swap", "id": id, "timestamp": 1,
            "from": "base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913", "fromAmount": "1", "to": to, "toAmount": "1",
            "transactionIds": [:], "status": status.rawValue,
        ]
        return try JSONDecoder().decode(ApiSwapActivity.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
