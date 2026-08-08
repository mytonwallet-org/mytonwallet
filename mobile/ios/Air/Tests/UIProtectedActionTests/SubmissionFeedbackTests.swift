import ProtectedAction
import Testing
import UIKit
@testable import UIProtectedAction
import WalletContext
import WalletCore

@Suite("Submission Feedback")
@MainActor
struct SubmissionFeedbackTests {
    @Test
    func `partial result presents counts before closing and never continues to success`() async {
        let host = UIViewController()
        var presentedFeedback: [SubmissionFeedback] = []
        var events: [Event] = []
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { _, feedback in
                presentedFeedback.append(feedback)
                events.append(.feedback)
                return true
            }
        )
        authorizationUI.setDismissHandler { events.append(.dismissAuthorization) }
        let remainingWork = ActionRemainingWork(
            completedUnitCount: 2,
            totalUnitCount: 3,
            error: TestError.failed
        )
        let result = ActionSubmissionResult<ApiMfaProtectedResult>.partiallyCommitted(
            receipt: ActionSubmissionReceipt(activityIds: ["activity"]),
            remainingWork: remainingWork
        )
        var successCompletionCount = 0

        let outcome = await SubmissionFeedbackHandler.handle(
            result,
            authorizationUI: authorizationUI,
            closeOriginatingFlow: { events.append(.closeFlow) }
        )
        if outcome == nil {
            successCompletionCount += 1
        }

        guard let firstFeedback = presentedFeedback.first,
              case .partiallyCommitted(let feedbackWork) = firstFeedback
        else {
            Issue.record("Expected partial feedback")
            return
        }
        guard let outcome, case .partiallyCommitted = outcome else {
            Issue.record("Expected partial outcome")
            return
        }
        #expect(feedbackWork.completedUnitCount == 2)
        #expect(feedbackWork.totalUnitCount == 3)
        let message = firstFeedback.message ?? ""
        #expect(message.contains(localizedIntegerString(2)))
        #expect(message.contains(localizedIntegerString(3)))
        #expect(!message.contains("%completed%"))
        #expect(!message.contains("%total%"))
        #expect(events == [.feedback, .dismissAuthorization, .closeFlow])
        #expect(successCompletionCount == 0)
    }

    @Test
    func `indeterminate result warns about duplicate submission before closing`() async {
        let host = UIViewController()
        var feedback: SubmissionFeedback?
        var dismissCount = 0
        var closeCount = 0
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { _, value in
                feedback = value
                return true
            }
        )
        authorizationUI.setDismissHandler { dismissCount += 1 }

        _ = await SubmissionFeedbackHandler.handle(
            ActionSubmissionResult<ApiMfaProtectedResult>.indeterminate(
                error: TestError.failed,
                receipt: nil
            ),
            authorizationUI: authorizationUI,
            closeOriginatingFlow: { closeCount += 1 }
        )

        guard let feedback, case .indeterminate = feedback else {
            Issue.record("Expected indeterminate feedback")
            return
        }
        #expect(feedback.message?.contains("may submit the action twice") == true)
        #expect(dismissCount == 1)
        #expect(closeCount == 1)
    }

    @Test
    func `not committed error preserves retryable flow`() async {
        let host = UIViewController()
        var feedback: SubmissionFeedback?
        var dismissCount = 0
        var closeCount = 0
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { _, value in
                feedback = value
                return true
            }
        )
        authorizationUI.setDismissHandler { dismissCount += 1 }

        let outcome = await SubmissionFeedbackHandler.handle(
            ActionSubmissionResult<ApiMfaProtectedResult>.notCommitted(TestError.failed),
            authorizationUI: authorizationUI,
            closeOriginatingFlow: { closeCount += 1 }
        )

        guard let feedback, case .notCommitted = feedback else {
            Issue.record("Expected not-committed feedback")
            return
        }
        guard let outcome, case .failed = outcome else {
            Issue.record("Expected failed outcome")
            return
        }
        #expect(dismissCount == 1)
        #expect(closeCount == 0)
    }

    @Test
    func `pending cancellation cannot suppress partial feedback`() async {
        let host = UIViewController()
        var feedbackCount = 0
        var closeCount = 0
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { _, _ in
                feedbackCount += 1
                return true
            }
        )
        authorizationUI.requestCompletionCancellation()

        _ = await SubmissionFeedbackHandler.handle(
            ActionSubmissionResult<ApiMfaProtectedResult>.partiallyCommitted(
                receipt: ActionSubmissionReceipt(),
                remainingWork: ActionRemainingWork(
                    completedUnitCount: 1,
                    totalUnitCount: 2,
                    error: TestError.failed
                )
            ),
            authorizationUI: authorizationUI,
            closeOriginatingFlow: { closeCount += 1 }
        )

        #expect(feedbackCount == 1)
        #expect(closeCount == 1)
    }

    @Test
    func `authorization UI presents terminal feedback at most once`() async {
        let host = UIViewController()
        var feedbackCount = 0
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { _, _ in
                feedbackCount += 1
                return true
            }
        )

        #expect(await authorizationUI.present(.indeterminate(TestError.failed)))
        #expect(await authorizationUI.present(.notCommitted(TestError.failed)) == false)
        #expect(feedbackCount == 1)
    }

    @Test
    func `committed result is left for success completion`() async {
        let host = UIViewController()
        var feedbackCount = 0
        var dismissCount = 0
        var closeCount = 0
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { _, _ in
                feedbackCount += 1
                return true
            }
        )
        authorizationUI.setDismissHandler { dismissCount += 1 }

        let outcome = await SubmissionFeedbackHandler.handle(
            ActionSubmissionResult<ApiMfaProtectedResult>.committed(ActionSubmissionReceipt()),
            authorizationUI: authorizationUI,
            closeOriginatingFlow: { closeCount += 1 }
        )

        if let _ = outcome {
            Issue.record("Committed result should continue to success completion")
        }
        #expect(feedbackCount == 0)
        #expect(dismissCount == 0)
        #expect(closeCount == 0)
    }
}

private enum Event: Equatable {
    case feedback
    case dismissAuthorization
    case closeFlow
}

private enum TestError: Error {
    case failed
}
