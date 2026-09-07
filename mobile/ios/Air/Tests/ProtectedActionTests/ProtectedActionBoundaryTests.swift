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
