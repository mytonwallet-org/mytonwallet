import ProtectedAction
import SwiftUI
import Testing
import UIKit
@testable import UIProtectedAction
import WalletCore

@Suite("Protected action executor")
@MainActor
struct UIProtectedActionExecutorTests {
    @Test
    func `invalid execution context reports a failure to the user`() async {
        let (presenter, window) = makeVisibleStack()
        defer { window.isHidden = true }
        let detachedOrigin = UIViewController()
        var presentedFeedback: [SubmissionFeedback] = []

        let outcome = await UIProtectedActionExecutor.execute(
            makeAction(),
            in: ExecutionContext(authorizationPresenter: presenter, flowOrigin: detachedOrigin),
            feedbackPresentation: { _, feedback in
                presentedFeedback.append(feedback)
                return true
            }
        )

        expectReportedConfigurationFailure(outcome, presentedFeedback)
    }

    @Test
    func `activity completion without sources reports a failure to the user`() async {
        let (presenter, window) = makeVisibleStack()
        defer { window.isHidden = true }
        var presentedFeedback: [SubmissionFeedback] = []

        let outcome = await UIProtectedActionExecutor.execute(
            makeAction(completion: .activity(ActivityCompletion(sources: [], context: .normal) { _, _ in false })),
            in: ExecutionContext(presenter),
            feedbackPresentation: { _, feedback in
                presentedFeedback.append(feedback)
                return true
            }
        )

        expectReportedConfigurationFailure(outcome, presentedFeedback)
    }

    private func makeVisibleStack() -> (presenter: UIViewController, window: UIWindow) {
        let presenter = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UINavigationController(rootViewController: presenter)
        window.isHidden = false
        return (presenter, window)
    }

    private func makeAction(
        completion: Completion<ApiMfaProtectedResult> = .dismissAuthorization
    ) -> ProtectedAction<TestHeader, ApiMfaProtectedResult> {
        ProtectedAction(
            account: MAccount(id: "0-mainnet", title: "Wallet", type: .mnemonic, byChain: [:]),
            software: .custom { _ in
                Issue.record("A misconfigured action must not be submitted")
                return .resolved(.notCommitted(CancellationError()))
            },
            hardware: nil,
            confirmation: Confirmation(title: "Confirm", header: TestHeader()),
            completion: completion
        )
    }

    private func expectReportedConfigurationFailure(
        _ outcome: Outcome<ApiMfaProtectedResult>,
        _ presentedFeedback: [SubmissionFeedback]
    ) {
        guard case .failed(let error) = outcome else {
            Issue.record("Expected a failed outcome")
            return
        }
        #expect(error is InvariantError)
        guard presentedFeedback.count == 1, case .notCommitted = presentedFeedback[0] else {
            Issue.record("Expected one not-committed feedback, got \(presentedFeedback)")
            return
        }
    }
}

private struct TestHeader: ConfirmationContent {
    var body: some View { EmptyView() }
    var compactRepresentation: some View { EmptyView() }
}
