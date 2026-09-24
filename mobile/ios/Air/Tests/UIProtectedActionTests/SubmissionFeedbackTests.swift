import ProtectedAction
import Testing
import UIKit
@testable import UIProtectedAction
import WalletCore

@Suite("Submission Feedback")
@MainActor
struct SubmissionFeedbackTests {
    @Test(arguments: [false, true])
    func `partial result presents counts before closing and never continues to success`(hasAuthorizationScreen: Bool) async {
        let host = UIViewController()
        let authorizationScreen = UIViewController()
        var presentedFeedback: [SubmissionFeedback] = []
        var events: [Event] = []
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { presenter, feedback in
                #expect(presenter === (hasAuthorizationScreen ? authorizationScreen : host))
                presentedFeedback.append(feedback)
                events.append(.feedback)
                return true
            }
        )
        if hasAuthorizationScreen {
            authorizationUI.setAlertHost(authorizationScreen)
            authorizationUI.setDismissHandler { events.append(.dismissAuthorization) }
        }
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
        #expect(events == (hasAuthorizationScreen ? [.feedback, .dismissAuthorization, .closeFlow] : [.feedback, .closeFlow]))
        #expect(successCompletionCount == 0)
    }

    @Test(arguments: [false, true])
    func `indeterminate result selects indeterminate feedback and closes the flow`(hasAuthorizationScreen: Bool) async {
        let host = UIViewController()
        let authorizationScreen = UIViewController()
        var feedback: SubmissionFeedback?
        var dismissCount = 0
        var closeCount = 0
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { presenter, value in
                #expect(presenter === (hasAuthorizationScreen ? authorizationScreen : host))
                feedback = value
                return true
            }
        )
        if hasAuthorizationScreen {
            authorizationUI.setAlertHost(authorizationScreen)
            authorizationUI.setDismissHandler { dismissCount += 1 }
        }

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
        #expect(dismissCount == (hasAuthorizationScreen ? 1 : 0))
        #expect(closeCount == 1)
    }

    @Test(arguments: [false, true])
    func `not committed error preserves retryable flow`(hasAuthorizationScreen: Bool) async {
        let host = UIViewController()
        let authorizationScreen = UIViewController()
        var feedback: SubmissionFeedback?
        var dismissCount = 0
        var closeCount = 0
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { presenter, value in
                #expect(presenter === (hasAuthorizationScreen ? authorizationScreen : host))
                feedback = value
                return true
            }
        )
        if hasAuthorizationScreen {
            authorizationUI.setAlertHost(authorizationScreen)
            authorizationUI.setDismissHandler { dismissCount += 1 }
        }

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
        #expect(dismissCount == (hasAuthorizationScreen ? 1 : 0))
        #expect(closeCount == 0)
    }

    @Test
    func `inline execution waits for error acknowledgement before allowing retry`() async throws {
        let host = UIViewController()
        var acknowledgement: CheckedContinuation<Bool, Never>?
        var didFinish = false
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: host,
            feedbackPresentation: { presenter, _ in
                #expect(presenter === host)
                return await withCheckedContinuation { acknowledgement = $0 }
            }
        )
        let task = Task {
            let outcome = await SubmissionFeedbackHandler.handle(
                ActionSubmissionResult<ApiMfaProtectedResult>.notCommitted(TestError.failed),
                authorizationUI: authorizationUI,
                closeOriginatingFlow: { Issue.record("A retryable error must keep the review screen") }
            )
            didFinish = true
            return outcome
        }
        for _ in 0..<100 where acknowledgement == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!didFinish)
        let pending = try #require(acknowledgement)
        pending.resume(returning: true)
        guard case .failed = await task.value else {
            Issue.record("Expected retryable failure after acknowledging the alert")
            return
        }
        #expect(didFinish)
    }

    @Test
    func `unavailable authorization screen falls back to the review screen`() async {
        let review = UIViewController()
        let authorizationScreen = UIViewController()
        var presenters: [UIViewController] = []
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: review,
            feedbackPresentation: { presenter, _ in
                presenters.append(presenter)
                return presenter === review
            }
        )
        authorizationUI.setAlertHost(authorizationScreen)

        #expect(await authorizationUI.present(.notCommitted(TestError.failed)))
        #expect(presenters == [authorizationScreen, review])
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
