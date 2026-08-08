import Testing
import UIKit
import ProtectedAction
@testable import UIProtectedAction
import WalletCore

@Suite("Screen Session")
@MainActor
struct ScreenSessionTests {
    @Test
    func `completion controls authorization disposal`() {
        let finish = Completion<ApiMfaProtectedResult>.finish { _ in }
        let handoff = Completion<ApiMfaProtectedResult>.handoff { _ in }
        let replace = Completion<ApiMfaProtectedResult>.replace { _ in nil }

        #expect(finish.authorizationCompletionBehavior == .popAuthorization)
        #expect(handoff.authorizationCompletionBehavior == .keepAuthorizationForReplacement)
        #expect(replace.authorizationCompletionBehavior == .keepAuthorizationForReplacement)
    }

    @Test
    func `committed completion without presentation cannot expose submitted action`() {
        let receipt = ActionSubmissionReceipt<ApiMfaProtectedResult>()
        var callbackCount = 0
        var closeCount = 0

        let callbackCompletions: [Completion<ApiMfaProtectedResult>] = [
            .finish { _ in callbackCount += 1 },
            .handoff { _ in callbackCount += 1 },
        ]
        for completion in callbackCompletions {
            completion.handleCommittedCompletionWithoutPresentation(
                receipt: receipt,
                closeOriginatingFlow: { closeCount += 1 }
            )
        }

        let closingCompletions: [Completion<ApiMfaProtectedResult>] = [
            .dismissAuthorization,
            .replace { _ in nil },
            .activity(.init(context: .swapConfirmation) { _, _ in true }),
        ]
        for completion in closingCompletions {
            completion.handleCommittedCompletionWithoutPresentation(
                receipt: receipt,
                closeOriginatingFlow: { closeCount += 1 }
            )
        }

        #expect(callbackCount == 2)
        #expect(closeCount == 3)
    }

    @Test
    func `authorization UI dismissal is consumed exactly once`() {
        var dismissalCount = 0
        let authorizationUI = AuthorizationUI()
        authorizationUI.setDismissHandler { dismissalCount += 1 }

        authorizationUI.dismiss()
        authorizationUI.dismiss()

        #expect(dismissalCount == 1)
    }

    @Test
    func `next authorization screen takes over dismissal ownership`() {
        let authorizationUI = AuthorizationUI()
        var oldDismissalCount = 0
        var nextDismissalCount = 0
        var transitionCount = 0
        authorizationUI.setDismissHandler { oldDismissalCount += 1 }
        authorizationUI.setNextScreenTransition { _ in
            transitionCount += 1
            return { nextDismissalCount += 1 }
        }

        guard case .succeeded = authorizationUI.transitionToNextScreen(UIViewController()) else {
            Issue.record("Expected the next screen transition to succeed")
            return
        }
        guard case .unavailable = authorizationUI.transitionToNextScreen(UIViewController()) else {
            Issue.record("Expected the next screen transition to be consumed")
            return
        }
        authorizationUI.dismiss()

        #expect(transitionCount == 1)
        #expect(oldDismissalCount == 0)
        #expect(nextDismissalCount == 1)
    }

    @Test
    func `next authorization screen replaces passcode in navigation history`() async {
        let feature = UIViewController()
        let passcode = UIViewController()
        let mfa = UIViewController()
        let navigationController = UINavigationController()
        navigationController.setViewControllers([feature, passcode], animated: false)

        #expect(
            AuthorizationSupport.push(
                mfa,
                replacing: passcode,
                in: navigationController
            )
        )
        for _ in 0..<10 {
            if !navigationController.viewControllers.contains(where: { $0 === passcode }) {
                break
            }
            await Task.yield()
        }

        #expect(navigationController.viewControllers.count == 2)
        #expect(navigationController.viewControllers[0] === feature)
        #expect(navigationController.viewControllers[1] === mfa)
    }

    @Test
    func `cancellation before continuation installation is retained`() async {
        let session = ScreenSession<ActionSubmissionResult<ApiMfaProtectedResult>>(
            stage: .authentication
        )

        #expect(!session.cancel(.taskCancelled))
        let resolution = await withCheckedContinuation { continuation in
            session.install(continuation)
        }

        guard case .cancelled(let cancellation) = resolution else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(cancellation.stage == .authentication)
        #expect(cancellation.reason == .taskCancelled)
    }

    @Test
    func `committed result wins over deferred cancellation`() async {
        let session = ScreenSession<ActionSubmissionResult<ApiMfaProtectedResult>>(
            stage: .authentication
        )
        let resolution = waitForResolution(session)
        await Task.yield()

        session.beginSubmission()
        #expect(!session.cancel(.taskCancelled))
        #expect(session.resolve(.committed(ActionSubmissionReceipt())))

        guard case .value(.committed, let shouldContinuePresentation) = await resolution.value else {
            Issue.record("Expected committed result")
            return
        }
        #expect(!shouldContinuePresentation)
    }

    @Test
    func `deferred cancellation wins over not committed result`() async {
        let session = ScreenSession<ActionSubmissionResult<ApiMfaProtectedResult>>(
            stage: .authentication
        )
        let resolution = waitForResolution(session)
        await Task.yield()

        session.beginSubmission()
        #expect(!session.cancel(.dismissed))
        #expect(!session.resolve(.notCommitted(TestError.failed)))

        guard case .cancelled(let cancellation) = await resolution.value else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(cancellation.reason == .dismissed)
    }

    @Test
    func `partially committed result wins over deferred cancellation`() async {
        let session = ScreenSession<ActionSubmissionResult<ApiMfaProtectedResult>>(
            stage: .ledger
        )
        let resolution = waitForResolution(session)
        await Task.yield()

        session.beginSubmission()
        #expect(!session.cancel(.closeButton))
        let result = ActionSubmissionResult<ApiMfaProtectedResult>.partiallyCommitted(
            receipt: ActionSubmissionReceipt(activityIds: ["activity"]),
            remainingWork: ActionRemainingWork(
                completedUnitCount: 1,
                totalUnitCount: 2,
                error: TestError.failed
            )
        )
        #expect(session.resolve(result))

        guard case .value(.partiallyCommitted, let shouldContinuePresentation) = await resolution.value else {
            Issue.record("Expected partial result")
            return
        }
        #expect(!shouldContinuePresentation)
    }

    @Test
    func `indeterminate result wins over deferred cancellation`() async {
        let session = ScreenSession<ActionSubmissionResult<ApiMfaProtectedResult>>(
            stage: .mfa
        )
        let resolution = waitForResolution(session)
        await Task.yield()

        session.beginSubmission()
        #expect(!session.cancel(.taskCancelled))
        #expect(session.resolve(.indeterminate(error: TestError.failed, receipt: nil)))

        guard case .value(.indeterminate, let shouldContinuePresentation) = await resolution.value else {
            Issue.record("Expected indeterminate result")
            return
        }
        #expect(!shouldContinuePresentation)
    }

    @Test
    func `cancellation after committed result is forwarded to completion`() async {
        let authorizationUI = AuthorizationUI()
        let session = ScreenSession<ActionSubmissionResult<ApiMfaProtectedResult>>(
            stage: .authentication
        )
        let resolution = waitForResolution(session)
        await Task.yield()

        #expect(session.resolve(.committed(ActionSubmissionReceipt())))
        _ = await resolution.value
        #expect(!session.cancel(.dismissed) {
            authorizationUI.requestCompletionCancellation()
        })

        var cancellationCount = 0
        authorizationUI.setCompletionCancellationHandler {
            cancellationCount += 1
        }
        authorizationUI.requestCompletionCancellation()
        #expect(cancellationCount == 1)
    }

    @Test
    func `deferred cancellation prevents transition into MFA`() async {
        let session = ScreenSession<SoftwareSubmission<ApiMfaProtectedResult>>(
            stage: .authentication
        )
        let resolution = Task { @MainActor in
            await withCheckedContinuation { continuation in
                session.install(continuation)
            }
        }
        await Task.yield()

        session.beginSubmission()
        #expect(!session.cancel(.taskCancelled))
        #expect(!session.resolve(.requiresMfa(ApiMfaProtectedResult(mfaRequestHash: "hash"))))

        guard case .cancelled(let cancellation) = await resolution.value else {
            Issue.record("Expected cancellation")
            return
        }
        #expect(cancellation.stage == .authentication)
        #expect(cancellation.reason == .taskCancelled)
    }

    private func waitForResolution(
        _ session: ScreenSession<ActionSubmissionResult<ApiMfaProtectedResult>>
    ) -> Task<ScreenResolution<ActionSubmissionResult<ApiMfaProtectedResult>>, Never> {
        Task { @MainActor in
            await withCheckedContinuation { continuation in
                session.install(continuation)
            }
        }
    }
}

private enum TestError: Error {
    case failed
}
