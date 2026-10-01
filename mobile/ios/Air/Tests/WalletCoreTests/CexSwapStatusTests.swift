import Foundation
import Testing
@testable import WalletCore

@Suite("CEX Swap Status")
struct CexSwapStatusTests {
    private let createdAt = Date(timeIntervalSince1970: 1_789_000_000)

    @Test(arguments: ["new", "waiting"])
    func `unpaid swaps expire at the three hour deadline`(status: String) throws {
        let swap = try makeSwap(status: status)
        let deadline = createdAt.addingTimeInterval(3 * 60 * 60)

        #expect(swap.cexWaitingDeadline == deadline)
        #expect(swap.displayStatus(at: deadline.addingTimeInterval(-1)).isPending)
        #expect(!swap.shouldShowCexSupport(at: deadline.addingTimeInterval(-1)))
        #expect(swap.displayStatus(at: deadline) == .expired)
        #expect(swap.shouldShowCexSupport(at: deadline))

        let accountChains: Set<ApiChain> = [.ethereum]
        #expect(swap.displayStatus(accountChains: accountChains, at: deadline.addingTimeInterval(-1))
            == (status == "new" ? .pending : .waitingForPayment))
        #expect(swap.displayStatus(accountChains: accountChains, at: deadline) == .expired)
    }

    @Test(arguments: ["confirming", "exchanging", "sending"])
    func `funded swaps remain pending and gain support after the deadline`(status: String) throws {
        let swap = try makeSwap(status: status)
        let later = createdAt.addingTimeInterval(4 * 60 * 60)

        #expect(swap.displayStatus(at: later) == .pending)
        #expect(swap.shouldShowCexSupport(at: later))
    }

    @Test
    func `held swaps show support immediately`() throws {
        let swap = try makeSwap(status: "hold")

        #expect(swap.displayStatus(at: createdAt) == .hold)
        #expect(swap.shouldShowCexSupport(at: createdAt))
    }

    @Test(arguments: ["finished", "confirmed"])
    func `completed swaps do not show delay or support warnings`(status: String) throws {
        let swap = try makeSwap(status: status)
        let later = createdAt.addingTimeInterval(4 * 60 * 60)

        #expect(swap.displayStatus(at: later) == .completed)
        #expect(!swap.shouldShowCexSupport(at: later))
    }

    @Test
    func `refunds and provider failures keep their distinct statuses`() throws {
        let later = createdAt.addingTimeInterval(4 * 60 * 60)
        #expect(try makeSwap(status: "refunded").displayStatus(at: later) == .refunded)
        #expect(try makeSwap(status: "failed").displayStatus(at: later) == .failed)
    }

    private func makeSwap(status: String) throws -> ApiSwapActivity {
        let payload: [String: Any] = [
            "kind": "swap", "id": "cex-swap", "timestamp": Int64(createdAt.timeIntervalSince1970 * 1000),
            "from": "toncoin", "fromAmount": "1", "to": "eth", "toAmount": "0.01",
            "transactionIds": [:], "status": "pending",
            "cex": ["status": status, "payinAddress": "deposit", "payoutAddress": "destination", "transactionId": "provider-id"],
        ]
        return try JSONDecoder().decode(ApiSwapActivity.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
