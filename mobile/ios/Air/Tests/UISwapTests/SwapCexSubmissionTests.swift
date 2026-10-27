import Foundation
import Testing
@testable import UISwap
import WalletContext
import WalletCore

@Suite("Cross-chain swap submission")
@MainActor
struct SwapCexSubmissionTests {
    @Test
    func `order creation timeout is safe to retry because no deposit was submitted`() async throws {
        let support = SwapCexSupport(
            createTransaction: { _, _, _ in throw URLError(.timedOut) },
            submit: { _, _, _ in
                Issue.record("Order creation did not complete")
                throw TestError.unexpectedSubmission
            }
        )

        do {
            _ = try await perform(support)
            Issue.record("Expected a timeout")
        } catch {
            #expect(actionSubmissionErrorDisposition(for: error) == .notCommitted)
            #expect((error as? NotSubmittedError)?.underlying is URLError)
        }
    }

    @Test(arguments: [false, true])
    func `order creation failure preserves its cause and never submits a deposit`(shouldTransfer: Bool) async throws {
        var submitCount = 0
        let cause = addressRejection(method: "swapCexCreateTransaction")
        let support = SwapCexSupport(
            createTransaction: { _, _, _ in throw cause },
            submit: { _, _, _ in
                submitCount += 1
                throw TestError.unexpectedSubmission
            }
        )

        do {
            _ = try await perform(support, shouldTransfer: shouldTransfer)
            Issue.record("Expected the order rejection")
        } catch {
            let result: ActionSubmissionResult<SwapExecutionResult> = actionSubmissionFailure(for: error)
            guard case .notCommitted(let underlying) = result else {
                Issue.record("Order creation must be known not submitted")
                return
            }
            #expect((underlying as? SdkError)?.backendMessage == "Address is not valid")
            #expect(!result.preventsRetry)
        }
        #expect(submitCount == 0)
    }

    @Test(arguments: ["cex", "networkFee"])
    func `incomplete deposit instructions are not submitted`(missingField: String) async throws {
        let response = try createResult(removing: missingField)
        var didSubmit = false
        let support = SwapCexSupport(
            createTransaction: { _, _, _ in response },
            submit: { _, _, _ in
                didSubmit = true
                throw TestError.unexpectedSubmission
            }
        )

        do {
            _ = try await perform(support)
            Issue.record("Expected invalid deposit instructions to fail")
        } catch {
            #expect(actionSubmissionErrorDisposition(for: error) == .notCommitted)
        }
        #expect(!didSubmit)
    }

    @Test
    func `deposit submission exception remains indeterminate`() async throws {
        let response = try createResult()
        var didSubmit = false
        let support = SwapCexSupport(
            createTransaction: { _, _, _ in response },
            submit: { _, _, _ in
                didSubmit = true
                throw SdkError.sdkNotReady(methodName: "swapCexSubmit", reason: "Bridge disconnected")
            }
        )

        do {
            _ = try await perform(support)
            Issue.record("Expected the submission exception")
        } catch {
            let result: ActionSubmissionResult<SwapExecutionResult> = actionSubmissionFailure(for: error)
            guard case .indeterminate = result else {
                Issue.record("A lost submission response must remain indeterminate")
                return
            }
            #expect(result.preventsRetry)
        }
        #expect(didSubmit)
    }

    @Test
    func `explicit deposit rejection remains not committed`() async throws {
        let response = try createResult()
        let support = SwapCexSupport(
            createTransaction: { _, _, _ in response },
            submit: { _, _, _ in
                try JSONDecoder().decode(ApiSwapSubmitResult.self, from: Data(#"{"error":"InsufficientBalance"}"#.utf8))
            }
        )

        do {
            _ = try await perform(support)
            Issue.record("Expected the deposit rejection")
        } catch {
            #expect(actionSubmissionErrorDisposition(for: error) == .notCommitted)
            #expect((error as? SdkError)?.backendMessage == "InsufficientBalance")
        }
    }

    @Test
    func `prepared deposit submits exactly once with the original options`() async throws {
        let response = try createResult()
        var submitCount = 0
        let support = SwapCexSupport(
            createTransaction: { accountId, token, request in
                #expect(accountId == "test-mainnet")
                #expect(token == "test-token")
                #expect(request.cexLabel == .changelly)
                return response
            },
            submit: { chain, options, swapId in
                submitCount += 1
                #expect(chain == .ton)
                #expect(swapId == "swap-id")
                #expect(options.toAddress == "deposit-address")
                #expect(options.amount == 36_450_000)
                #expect(options.fee == 30_000_000)
                #expect(options.enclaveToken == "test-token")
                return try JSONDecoder().decode(ApiSwapSubmitResult.self, from: Data(#"{"mfaRequestHash":"mfa-hash"}"#.utf8))
            }
        )

        let result = try await perform(support)
        #expect(submitCount == 1)
        #expect(result.swapId == "swap-id")
        #expect(result.mfaRequestHash == "mfa-hash")
    }

    @Test
    func `external deposit flow returns the order without submitting`() async throws {
        let response = try createResult(removing: "networkFee")
        let support = SwapCexSupport(
            createTransaction: { _, _, _ in response },
            submit: { _, _, _ in
                Issue.record("External funding must not submit a deposit")
                throw TestError.unexpectedSubmission
            }
        )

        let result = try await perform(support, shouldTransfer: false)
        #expect(result.activity?.id == response.activity.id)
        #expect(result.swapId == nil)
    }

    private func perform(_ support: SwapCexSupport, shouldTransfer: Bool = true) async throws -> SwapExecutionResult {
        try await support.swapCexCreateTransaction(
            accountId: "test-mainnet",
            sellingToken: .TON_USDT,
            request: ApiSwapBuildRequest(
                from: "ton-usdt", to: "ltc", fromAddress: "source-address",
                cexLabel: .changelly, fromAmount: MDouble(36.45)
            ),
            shouldTransfer: shouldTransfer,
            enclaveToken: "test-token"
        )
    }

    private func createResult(removing field: String? = nil) throws -> ApiSwapCexCreateTransactionResult {
        let data = Data(#"""
        {
          "id":"swap-id", "timestamp":1770000000000,
          "from":"ton-usdt", "fromAmount":"36.45", "to":"ltc", "toAmount":"0.6",
          "status":"pendingTrusted", "networkFee":"0.03", "swapFee":"0.004",
          "hashes":[], "transactionIds":{}, "cexLabel":"changelly",
          "cex":{"payinAddress":"deposit-address", "payoutAddress":"recipient-address",
                 "status":"waiting", "transactionId":"provider-id"}
        }
        """#.utf8)
        var swap = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        if let field { swap.removeValue(forKey: field) }
        var activity = swap
        activity["kind"] = "swap"
        activity["id"] = "swap-id::backend-swap"
        return try JSONDecoder().decode(
            ApiSwapCexCreateTransactionResult.self,
            from: JSONSerialization.data(withJSONObject: ["swap": swap, "activity": activity])
        )
    }

    private func addressRejection(method: String) -> SdkError {
        .javaScriptException(SdkJavaScriptException(
            methodName: method,
            exceptionMessage: #"{"message":"Address is not valid","additionalData":{"statusCode":400}}"#
        ))
    }
}

private enum TestError: Error {
    case unexpectedSubmission
}
