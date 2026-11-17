import Foundation
import GRDB
import Testing
@testable import WalletCore

@Suite("Swap settlement")
struct SwapSettlementTests {
    @Test(arguments: ["lifi", "layerzero"], [false, true])
    func `late polling responses preserve settlement while other SDK patches stay authoritative`(
        provider: String,
        isPollingResponse: Bool
    ) async throws {
        let accountId = UUID().uuidString + "-mainnet"
        let store = try await makeStore(accountId: accountId)
        let pending = try decodeActivity(makePayload(provider: provider, status: "pendingTrusted"))
        var settledPayload = makePayload(provider: provider, status: "completed")
        settledPayload["toAmount"] = "0.975"
        if provider == "lifi" {
            settledPayload["to"] = "base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
            settledPayload["lifi"] = ["quotedTo": "arbitrum:native", "quotedToAmount": "2", "outcome": "partial"]
        } else {
            settledPayload["layerzero"] = ["quoteId": "quote", "status": "SUCCEEDED"]
        }
        let settled = try decodeActivity(settledPayload)
        var sourcePayload = makePayload(provider: provider, status: "completed")
        sourcePayload["id"] = "source-action"
        sourcePayload.removeValue(forKey: provider)
        let source = try decodeActivity(sourcePayload)
        await store.applyActivitiesPatch(
            accountId: accountId,
            patch: .init(accountId: accountId, upsert: [settled, source], removeIds: []),
            visibleChain: nil
        )

        sourcePayload["status"] = "pendingTrusted"
        sourcePayload["shouldHide"] = true
        let incomingSource = try decodeActivity(sourcePayload)
        let delayedPatch = ApiActivitiesPatch(accountId: accountId, upsert: [pending, incomingSource], removeIds: [])
        if isPollingResponse {
            _ = await store.applyFetchedCexSwaps(
                accountId: accountId,
                result: .init(nonExistentIds: [], swaps: [], patch: delayedPatch)
            )
        } else {
            await store.applyActivitiesPatch(accountId: accountId, patch: delayedPatch, visibleChain: nil)
        }

        let state = await store.getAccountState(accountId)
        let expected = isPollingResponse ? settled : pending
        #expect(state.byId?[pending.id] == expected)
        #expect(state.idsBySlug?[expected.swap!.to] == [pending.id])
        #expect(state.byId?[source.id] == incomingSource)
        #expect(state.idsMain == [pending.id])
    }

    @Test(arguments: ["lifi", "layerzero"])
    func `provider settlement survives the native reconciliation round trip`(provider: String) throws {
        let payload = makePayload(provider: provider, status: "pendingTrusted")
        let activity = try decodeActivity(payload)
        let encoded = try JSONEncoder().encode(activity)
        let restored = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect((restored[provider] as? NSDictionary) == (payload[provider] as? NSDictionary))
        #expect(restored["msgHash"] as? String == payload["msgHash"] as? String)
    }

    @Test(arguments: ["lifi", "layerzero"], ["completed", "failed", "confirmed"])
    func `fresh provider history corrects a source leg verdict without settlement evidence`(provider: String, status: String) throws {
        var cachedPayload = makePayload(provider: provider, status: status)
        cachedPayload.removeValue(forKey: provider)
        let cached = try decodeActivity(cachedPayload)
        let pending = try decodeActivity(makePayload(provider: provider, status: "pendingTrusted"))

        let corrected = preserveActivityStatusProgress(existingActivity: cached, incomingActivity: pending)

        #expect(corrected.swap?.status == .pendingTrusted)
        #expect(corrected.swap?.displayStatus() == .pending)
    }

    @Test(arguments: ["completed", "partial", "refunded"])
    func `stale LI FI history preserves the settled asset amount and outcome`(outcome: String) throws {
        let status = outcome == "refunded" ? "failed" : "completed"
        var settledPayload = makePayload(provider: "lifi", status: status)
        settledPayload["to"] = "base-0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"
        settledPayload["toAmount"] = "0.975"
        var settlement = try #require(settledPayload["lifi"] as? [String: Any])
        settlement["outcome"] = outcome
        settlement["received"] = [
            "chain": "base", "tokenAddress": "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913",
            "symbol": "USDC", "decimals": 6, "amount": "0.975",
        ]
        settledPayload["lifi"] = settlement
        let settled = try decodeActivity(settledPayload)
        let pending = try decodeActivity(makePayload(provider: "lifi", status: "pendingTrusted"))

        let result = preserveActivityStatusProgress(existingActivity: settled, incomingActivity: pending)
        let encoded = try JSONEncoder().encode(result)
        let restored = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(result.swap?.status == settled.swap?.status)
        #expect(result.swap?.to == settled.swap?.to)
        #expect(result.swap?.toAmount == settled.swap?.toAmount)
        #expect((restored["lifi"] as? NSDictionary) == (settledPayload["lifi"] as? NSDictionary))
    }

    @Test
    func `stale LayerZero history preserves the delivered amount and status`() throws {
        var settledPayload = makePayload(provider: "layerzero", status: "completed")
        settledPayload["toAmount"] = "0.975"
        settledPayload["layerzero"] = ["quoteId": "quote", "status": "DELIVERED"]
        let settled = try decodeActivity(settledPayload)
        let pending = try decodeActivity(makePayload(provider: "layerzero", status: "pendingTrusted"))

        let result = preserveActivityStatusProgress(existingActivity: settled, incomingActivity: pending)
        let encoded = try JSONEncoder().encode(result)
        let restored = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        #expect(result.swap?.status == .completed)
        #expect(result.swap?.toAmount == settled.swap?.toAmount)
        #expect((restored["layerzero"] as? NSDictionary) == (settledPayload["layerzero"] as? NSDictionary))
    }

    private func makeStore(accountId: String) async throws -> _ActivityStore {
        let database = try DatabaseQueue()
        try makeMigrator().migrate(database)
        try await database.write { database in
            try MAccount(
                id: accountId, title: "Settlement test", type: .view,
                byChain: ["ton": AccountChain(address: "test")]
            ).insert(database)
        }
        let store = _ActivityStore()
        await store.use(db: database)
        return store
    }

    private func makePayload(provider: String, status: String) -> [String: Any] {
        [
            "kind": "swap", "id": "swap::backend-swap", "timestamp": 1,
            "from": "eth", "fromAmount": "1", "to": "arbitrum", "toAmount": "2",
            "hashes": [], "msgHash": "0x" + String(repeating: "a", count: 64),
            "transactionIds": [:], "status": status,
            provider: provider == "lifi"
                ? ["quotedTo": "arbitrum:native", "quotedToAmount": "2"]
                : ["quoteId": "quote", "status": "PENDING"],
        ]
    }

    private func decodeActivity(_ payload: [String: Any]) throws -> ApiActivity {
        try JSONDecoder().decode(ApiActivity.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
