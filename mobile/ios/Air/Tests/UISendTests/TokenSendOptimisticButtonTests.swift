import Dependencies
import Foundation
import Testing
import UIComponents
@testable import UISend
import WalletContext
@testable import WalletCore
import WalletResources

@Suite("Send optimistic button")
@MainActor
struct TokenSendOptimisticButtonTests {
    init() { _ = WalletResourcesBundle.bundle.load() }

    @Test(arguments: [false, true], [false, true])
    func `editing 1 to 10 with a balance of 500 preserves presentation until validation finishes`(rejected: Bool, gasless: Bool) async throws {
        let harness = try Harness(gasless: gasless)
        let model = harness.model
        defer { model.draft.pause() }
        let button = WButton()
        let presenter = DraftButtonPresenter(button: button)
        apply(model.primaryAction, to: presenter)
        #expect(!button.isEnabled)
        try await harness.publishDraft()
        #expect(model.primaryAction == .continueToReview)
        apply(model.primaryAction, to: presenter)
        #expect(button.isEnabled && button.isUserInteractionEnabled)
        let previousFee = try #require(model.showingFee)

        model.setTokenAmount(10 * harness.unit)
        #expect(model.primaryAction == .validating)
        #expect(model.showingFee == previousFee)
        #expect(model.currentDraftSnapshot == nil)
        #expect(throws: (any Error).self) { try model.makeConfirmedSend() }
        apply(model.primaryAction, to: presenter)
        #expect(button.isEnabled)
        #expect(button.showLoading)
        #expect(!button.isUserInteractionEnabled)

        model.draft.synchronize()
        try await harness.publishDraft(error: rejected ? "InsufficientBalance" : nil)
        apply(model.primaryAction, to: presenter)
        #expect(!button.showLoading)
        if rejected {
            #expect(model.primaryAction == .unavailable(.insufficientFee))
            #expect(!button.isEnabled && !button.isUserInteractionEnabled)
            #expect(throws: (any Error).self) { try model.makeConfirmedSend() }
        } else {
            #expect(model.primaryAction == .continueToReview)
            #expect(button.isEnabled && button.isUserInteractionEnabled)
            #expect(throws: Never.self) { try model.makeConfirmedSend() }

            model.setTokenAmount(501 * harness.unit)
            #expect(model.primaryAction == .unavailable(.insufficientAmount))
            apply(model.primaryAction, to: presenter)
            #expect(!button.isEnabled && !button.showLoading)
            #expect(throws: (any Error).self) { try model.makeConfirmedSend() }
        }
    }
}

@MainActor private func apply(_ action: TokenSendPrimaryAction, to presenter: DraftButtonPresenter) {
    presenter.apply(.init(title: .text("Continue"), isEnabled: action.isEnabled, showLoading: action.isLoading))
}

@MainActor private final class Harness {
    let probe = DraftProbe()
    let gasless: Bool
    let unit: BigInt
    let balances: AccountBalances
    let model: TokenSendModel

    init(gasless: Bool) throws {
        self.gasless = gasless
        let token = gasless ? ApiToken.TON_USDT : .TONCOIN
        let unit: BigInt = gasless ? 1_000_000 : 1_000_000_000
        self.unit = unit
        let accountId = "sendoptimism\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))-mainnet"
        let store = _BalancesStore.liveValue
        balances = store.for(accountId: accountId)
        var tokenBalances: [String: BigInt] = [TONCOIN_SLUG: 0]
        tokenBalances[token.slug] = 500 * unit
        balances.replaceAll(byChain: [.ton: tokenBalances])
        let feeQuote = try makeDraft()
        model = withDependencies {
            $0[_TokenStore.self] = TokenStore
            $0[_BalancesStore.self] = store
        } operation: { [probe] in
            TokenSendModel(
                accountContext: AccountContext(source: .constant(MAccount(
                    id: accountId, title: nil, type: .mnemonic,
                    byChain: [.ton: AccountChain(address: String(repeating: "B", count: 48))]
                ))),
                configuration: .init(
                    mode: .send, initialAddress: recipientAddress, initialAmount: unit, isMaxAmount: false,
                    initialTokenSlug: token.slug, jettonAddress: nil, initialComment: "",
                    binaryPayload: nil, stateInit: nil
                ),
                flow: TokenSendFlow(api: .init(
                    checkDraft: { _, options in
                        if options.amount == nil { return feeQuote }
                        return try await probe.load()
                    },
                    submit: { _, _ in throw CancellationError() }
                )),
                recipientResolver: .init { request in
                    [.ton: RecipientCandidate(resolvedAddress: request.input)]
                }
            )
        }
    }

    func publishDraft(error: String? = nil) async throws {
        try await waitUntil { self.probe.hasPendingLoad }
        try probe.finish(makeDraft(error: error, gasless: gasless))
        try await waitUntil { self.model.currentDraftSnapshot != nil }
    }
}

@MainActor private final class DraftProbe {
    private var continuation: CheckedContinuation<ApiCheckTransactionDraftResult, any Error>?
    var hasPendingLoad: Bool { continuation != nil }

    func load() async throws -> ApiCheckTransactionDraftResult {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(_ result: ApiCheckTransactionDraftResult) throws {
        let pending = try #require(continuation)
        continuation = nil
        pending.resume(returning: result)
    }
}

private let recipientAddress = String(repeating: "A", count: 48)

private func makeDraft(error: String? = nil, gasless: Bool = false) throws -> ApiCheckTransactionDraftResult {
    var json: [String: Any] = [
        "resolvedAddress": recipientAddress,
        "explainedFee": [
            "isGasless": gasless, "canTransferFullBalance": false,
            "fullFee": ["precision": "exact", "terms": gasless ? ["token": "100000", "native": "0"] : ["native": "50000000"], "nativeSum": "50000000"],
            "realFee": ["precision": "exact", "terms": gasless ? ["token": "100000", "native": "0"] : ["native": "10000000"], "nativeSum": "10000000"],
        ],
    ]
    json["error"] = error
    if gasless {
        json["diesel"] = [
            "status": "available", "amount": "100000",
            "nativeAmount": "50000000", "remainingFee": "0", "realFee": "10000000",
        ]
    }
    return try JSONDecoder().decode(ApiCheckTransactionDraftResult.self, from: JSONSerialization.data(withJSONObject: json))
}

@MainActor private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(3)
    while !condition() {
        try #require(ContinuousClock.now < deadline, "Timed out waiting for send draft")
        try await Task.sleep(for: .milliseconds(5))
    }
}
