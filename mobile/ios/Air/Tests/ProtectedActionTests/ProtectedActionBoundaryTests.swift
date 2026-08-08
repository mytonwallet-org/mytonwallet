import SwiftUI
import Testing
import UIKit
@testable import ProtectedAction
import WalletContext
@testable import WalletCore

@Suite("Protected Action Boundary", .serialized)
@MainActor
struct ProtectedActionBoundaryTests {
    @Test
    func `confirmation presents authorization UI before biometrics by default`() {
        let confirmation = Confirmation(
            title: "Confirm test action",
            header: TestConfirmationContent()
        )

        #expect(confirmation.biometricPolicy == .onAuthorizationScreen)
    }

    @Test
    func `executor implementation can be replaced by a feature test`() async {
        let previousExecutor = ProtectedActionExecutor
        defer { ProtectedActionExecutor = previousExecutor }
        RecordingProtectedActionExecutor.lastTitle = nil
        ProtectedActionExecutor = RecordingProtectedActionExecutor.self

        let action = ProtectedAction(
            account: .sampleMnemonic,
            software: .single { _ in ApiMfaProtectedResult() },
            hardware: nil,
            confirmation: Confirmation(
                title: "Confirm test action",
                header: TestConfirmationContent()
            )
        )

        let outcome = await ProtectedActionExecutor.execute(
            action,
            on: UIViewController()
        )

        #expect(RecordingProtectedActionExecutor.lastTitle == "Confirm test action")
        guard case .cancelled = outcome else {
            Issue.record("Expected the recording executor outcome")
            return
        }
    }

    @Test
    func `hardware operation is independent from its UI implementation`() async {
        var reportedProgress: (Int, Int)?
        let operation = HardwareOperation<Int>.custom { context in
            context.updateProgress(completedUnitCount: 1, totalUnitCount: 2)
            return .committed(ActionSubmissionReceipt(payload: 42))
        }
        let context = HardwareOperationContext { completed, total in
            reportedProgress = (completed, total)
        }

        let result = await operation.perform(context: context)

        #expect(reportedProgress?.0 == 1)
        #expect(reportedProgress?.1 == 2)
        guard case .committed(let receipt) = result else {
            Issue.record("Expected a committed hardware result")
            return
        }
        #expect(receipt.payload == 42)
    }

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

@MainActor
private struct TestConfirmationContent: ConfirmationContent {
    var body: some View { EmptyView() }
    var compactRepresentation: some View { EmptyView() }
}

@MainActor
private enum RecordingProtectedActionExecutor: ProtectedActionExecuting {
    static var lastTitle: String?

    static func execute<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        _ action: ProtectedAction<HeaderView, Result>,
        in context: ExecutionContext
    ) async -> Outcome<Result> {
        lastTitle = action.confirmation.title
        return .cancelled
    }
}
