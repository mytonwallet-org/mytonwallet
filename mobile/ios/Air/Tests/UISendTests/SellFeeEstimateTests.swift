import Foundation
import Testing
@testable import UISend
import WalletContext
import WalletCore

@Suite("Sell fee failures")
struct SellFeeEstimateTests {
    @Test(arguments: ["ServerError", "InsufficientBalance", "InvalidToAddress"])
    func `a failed draft without a fee cannot become an estimate`(error: String) async throws {
        let draft = try decodeDraft("{\"error\":\"\(error)\"}")
        let api: @Sendable () async throws -> ApiCheckTransactionDraftResult = { draft }
        let expected = try #require(draft.error)

        await #expect(throws: expected) {
            try await sellAmount(api)
        }
    }

    @Test
    func `transport failures cannot become a full-balance sale`() async {
        let api: @Sendable () async throws -> ApiCheckTransactionDraftResult = { throw Failure.offline }
        await #expect(throws: Failure.offline) {
            try await sellAmount(api)
        }
    }

    @Test(arguments: [false, true])
    func `a usable fee reserves gas even when a full-balance probe is insufficient`(insufficient: Bool) async throws {
        let draft = try feeDraft(error: insufficient ? "InsufficientBalance" : nil)
        let api: @Sendable () async throws -> ApiCheckTransactionDraftResult = { draft }
        #expect(try await sellAmount(api) == 95)
    }

    @Test
    func `fatal errors remain failures even with a fee`() async throws {
        let draft = try feeDraft(error: "ServerError")
        let api: @Sendable () async throws -> ApiCheckTransactionDraftResult = { draft }
        await #expect(throws: ApiAnyDisplayError.serverError) {
            try await sellAmount(api)
        }
    }

    @Test
    func `Sell requires a usable full fee`() async throws {
        let draft = try decodeDraft("{}")
        await #expect(throws: ApiAnyDisplayError.serverError) {
            try await sellAmount { draft }
        }
    }

    @Test
    func `fee estimation can recover after a failed request`() async throws {
        let recovered = try feeDraft(error: nil)
        let source = RecoveringDraft(draft: recovered)
        let api: @Sendable () async throws -> ApiCheckTransactionDraftResult = { try await source.next() }
        await #expect(throws: Failure.offline) {
            try await sellAmount(api)
        }
        #expect(try await sellAmount(api) == 95)
    }

    @Test
    func `full-native-balance chains keep their existing amount without a fee probe`() async throws {
        let amount = try await SellFeeEstimate.maximumAmount(
            accountId: "fee-test-mainnet", tokenSlug: TONCOIN_SLUG, chain: .ton, balance: 100,
            checkDraft: { _, _ in throw Failure.offline }
        )
        #expect(amount == 100)
    }

    private func sellAmount(_ load: @Sendable () async throws -> ApiCheckTransactionDraftResult) async throws -> BigInt? {
        try await SellFeeEstimate.maximumAmount(
            accountId: "fee-test-mainnet", tokenSlug: "eth", chain: .ethereum, balance: 100, checkDraft: { _, _ in try await load() }
        )
    }
}

private enum Failure: Error { case offline }

private actor RecoveringDraft {
    let draft: ApiCheckTransactionDraftResult
    var failed = false

    init(draft: ApiCheckTransactionDraftResult) { self.draft = draft }

    func next() throws -> ApiCheckTransactionDraftResult {
        if !failed {
            failed = true
            throw Failure.offline
        }
        return draft
    }
}

private func decodeDraft(_ json: String) throws -> ApiCheckTransactionDraftResult {
    try JSONDecoder().decode(ApiCheckTransactionDraftResult.self, from: Data(json.utf8))
}

private func feeDraft(error: String?) throws -> ApiCheckTransactionDraftResult {
    var json: [String: Any] = [
        "explainedFee": [
            "isGasless": false, "canTransferFullBalance": false,
            "fullFee": ["precision": "exact", "terms": ["native": "5"], "nativeSum": "5"],
        ],
    ]
    json["error"] = error
    return try JSONDecoder().decode(ApiCheckTransactionDraftResult.self, from: JSONSerialization.data(withJSONObject: json))
}
