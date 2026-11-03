import Foundation
import Testing
@testable import ProtectedAction
import WalletContext
@testable import WalletCore

@Suite("Protected Action Boundary")
@MainActor
struct ProtectedActionBoundaryTests {
    @Test
    func `single hardware operation classifies success and failure`() async {
        let successful = HardwareOperation<Int>.single {
            ActionSubmissionReceipt(payload: 42)
        }
        let notCommitted = HardwareOperation<Int>.single {
            throw DisplayError(text: "Rejected")
        }
        let indeterminate = HardwareOperation<Int>.single {
            throw TestError.failed
        }
        let context = HardwareOperationContext { _, _ in }

        guard case .committed(let receipt) = await successful.perform(context: context) else {
            Issue.record("Expected a committed result")
            return
        }
        #expect(receipt.payload == 42)
        guard case .notCommitted = await notCommitted.perform(context: context) else {
            Issue.record("Expected a not-committed result")
            return
        }
        guard case .indeterminate = await indeterminate.perform(context: context) else {
            Issue.record("Expected an indeterminate result")
            return
        }
    }

    @Test(arguments: ["RejectedByUser", "InsufficientBalance", "ConnectionBroken"])
    func `staking hardware refusal preserves the SDK error and allows retry`(errorCode: String) async throws {
        let response = try JSONDecoder().decode(
            ApiMfaProtectedResult.self,
            from: Data("{\"error\":\"\(errorCode)\"}".utf8)
        )
        let operation = HardwareOperation<ApiMfaProtectedResult>.single {
            ActionSubmissionReceipt(activityIds: [try response.requireActivityId()])
        }

        let result = await operation.perform(context: HardwareOperationContext { _, _ in })

        guard case .notCommitted(let error) = result,
              let sdkError = error as? SdkError else {
            Issue.record("Expected an explicit SDK refusal")
            return
        }
        #expect(sdkError.backendMessage == errorCode)
        #expect(sdkError.errorDescription == ApiAnyDisplayError.from(errorCode)?.toLocalized)
        #expect(!result.preventsRetry)
        #expect(result.receipt == nil)
    }

    @Test
    func `staking hardware success preserves its activity`() async throws {
        let response = try JSONDecoder().decode(
            ApiMfaProtectedResult.self,
            from: Data(#"{"activityId":"stake-activity"}"#.utf8)
        )
        let operation = HardwareOperation<ApiMfaProtectedResult>.single {
            ActionSubmissionReceipt(activityIds: [try response.requireActivityId()])
        }

        let result = await operation.perform(context: HardwareOperationContext { _, _ in })

        guard case .committed(let receipt) = result else {
            Issue.record("Expected a committed staking result")
            return
        }
        #expect(receipt.activityIds == ["stake-activity"])
    }

    @Test(arguments: ["UnsuccesfulTransfer", "UnsuccessfulTransfer"])
    func `staking broadcast failure remains indeterminate`(errorCode: String) async throws {
        let response = try JSONDecoder().decode(
            ApiMfaProtectedResult.self,
            from: Data("{\"error\":\"\(errorCode)\"}".utf8)
        )
        let operation = HardwareOperation<ApiMfaProtectedResult>.single {
            ActionSubmissionReceipt(activityIds: [try response.requireActivityId()])
        }

        let result = await operation.perform(context: HardwareOperationContext { _, _ in })

        guard case .indeterminate(let error, _) = result,
              let sdkError = error as? SdkError else {
            Issue.record("Expected an indeterminate broadcast result")
            return
        }
        #expect(sdkError.backendMessage == errorCode)
        #expect(result.preventsRetry)
        #expect(result.receipt == nil)
    }

    @Test
    func `staking hardware response without an activity or error remains indeterminate`() async throws {
        let response = try JSONDecoder().decode(ApiMfaProtectedResult.self, from: Data("{}".utf8))
        let operation = HardwareOperation<ApiMfaProtectedResult>.single {
            ActionSubmissionReceipt(activityIds: [try response.requireActivityId()])
        }

        let result = await operation.perform(context: HardwareOperationContext { _, _ in })

        guard case .indeterminate = result else {
            Issue.record("Expected an indeterminate staking result")
            return
        }
        #expect(result.preventsRetry)
        #expect(result.receipt == nil)
    }

    @Test
    func `MFA confirmation preserves transaction hash correlation`() async {
        let operation = SoftwareOperation<TestMfaResult>.single { _ in
            TestMfaResult(mfaRequestHash: "request-hash")
        }
        let result = await operation.confirmMfa(
            result: TestMfaResult(mfaRequestHash: "request-hash"),
            accountId: "account",
            request: ApiMfaRequest(
                payload: "payload",
                signature: "signature",
                isConfirmed: true,
                txHash: "transaction-hash"
            )
        )

        guard case .committed(let receipt) = result else {
            Issue.record("Expected a committed MFA result")
            return
        }
        #expect(receipt.externalMessageHashes == ["transaction-hash"])
    }
}

private enum TestError: Error {
    case failed
}

private struct TestMfaResult: MfaProtectedActionResult {
    let mfaRequestHash: String?
}
