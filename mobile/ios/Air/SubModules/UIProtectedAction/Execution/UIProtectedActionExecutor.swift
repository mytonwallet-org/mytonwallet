import SwiftUI
import UIKit
import ProtectedAction
import UIComponents
import WalletContext
import WalletCore

private let executorLog = Log("ProtectedActionExecutor")

@MainActor
public enum UIProtectedActionExecutor: ProtectedActionExecuting {
    public static func execute<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        _ action: ProtectedAction<HeaderView, Result>,
        in context: ExecutionContext
    ) async -> Outcome<Result> {
        let viewController = context.authorizationPresenter
        guard let executionSession = ExecutionSessionRegistry.shared.acquire(in: context) else {
            executorLog.error("Ignored concurrent protected action execution for the same presentation surface")
            return .cancelled
        }
        defer { executionSession.finish() }
        if let error = executionSession.configurationError {
            logInvariant(error)
            return .failed(error)
        }
        guard executionSession.canPresentAuthorization else {
            executorLog.info("Protected action presenter is no longer visible")
            return .cancelled
        }
        let authorizationUI = AuthorizationUI(
            fallbackAlertHost: viewController.navigationController ?? viewController
        )
        let activityWaiter: ActivityWaiter?
        if case .activity(let completion) = action.completion {
            guard !completion.sources.isEmpty else {
                let error = InvariantError.invalidConfiguration("activity sources are empty")
                logInvariant(error)
                return .failed(error)
            }
            activityWaiter = ActivityWaiter(
                accountId: action.account.id,
                sources: completion.sources,
                timeout: completion.timeout
            )
        } else {
            activityWaiter = nil
        }
        if let activityWaiter {
            authorizationUI.setSubmissionStartedHandler { [weak activityWaiter] in
                activityWaiter?.markSubmissionStarted()
            }
        }

        let authorization = await AuthorizationCoordinator.authorize(
            action: action,
            on: viewController,
            completionBehavior: action.completion.authorizationCompletionBehavior,
            authorizationUI: authorizationUI,
            isPresentationValid: { executionSession.canPresentAuthorization }
        )

        switch authorization {
        case .cancelled(let cancellation):
            activityWaiter?.cancel()
            authorizationUI.clear()
            executorLog.info(
                "Protected action cancelled during \(cancellation.stage.rawValue, .public): \(cancellation.reason.rawValue, .public)"
            )
            return .cancelled

        case .failed(let error):
            activityWaiter?.cancel()
            logFailure(error)
            await authorizationUI.present(.notCommitted(error))
            authorizationUI.dismiss()
            return .failed(error)

        case .value(let submission, let shouldPresentCompletion):
            return await finish(
                submission,
                shouldPresentCompletion: shouldPresentCompletion,
                action: action,
                activityWaiter: activityWaiter,
                authorizationUI: authorizationUI,
                executionSession: executionSession
            )
        }
    }

    private static func finish<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        _ submission: ActionSubmissionResult<Result>,
        shouldPresentCompletion: Bool,
        action: ProtectedAction<HeaderView, Result>,
        activityWaiter: ActivityWaiter?,
        authorizationUI: AuthorizationUI,
        executionSession: ExecutionSession
    ) async -> Outcome<Result> {
        if let outcome = await SubmissionFeedbackHandler.handle(
            submission,
            authorizationUI: authorizationUI,
            closeOriginatingFlow: executionSession.closeOriginatingFlow
        ) {
            activityWaiter?.cancel()
            logTerminalOutcome(outcome)
            return outcome
        }
        guard case .committed(let receipt) = submission else {
            let error = InvariantError.missingResult("terminal submission outcome")
            logInvariant(error)
            authorizationUI.dismiss()
            executionSession.closeOriginatingFlow()
            return .failed(error)
        }
        return await finishCommitted(
            receipt,
            shouldPresentCompletion: shouldPresentCompletion,
            action: action,
            activityWaiter: activityWaiter,
            authorizationUI: authorizationUI,
            executionSession: executionSession
        )
    }

    private static func finishCommitted<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        _ receipt: ActionSubmissionReceipt<Result>,
        shouldPresentCompletion: Bool,
        action: ProtectedAction<HeaderView, Result>,
        activityWaiter: ActivityWaiter?,
        authorizationUI: AuthorizationUI,
        executionSession: ExecutionSession
    ) async -> Outcome<Result> {
        var didRequestCompletionCancellation = false
        authorizationUI.setCompletionCancellationHandler {
            didRequestCompletionCancellation = true
            activityWaiter?.cancel()
        }
        if Task.isCancelled
            || !shouldPresentCompletion
            || didRequestCompletionCancellation
            || !executionSession.isPresentationContextAlive {
            executorLog.info("Protected action committed with completion suppressed")
            activityWaiter?.cancel()
            finishCommittedWithoutPresentation(
                action.completion,
                receipt: receipt,
                authorizationUI: authorizationUI,
                executionSession: executionSession
            )
            return .completed(receipt)
        }

        switch action.completion {
        case .dismissAuthorization:
            activityWaiter?.cancel()
            authorizationUI.clear()

        case .finish(let completion), .handoff(let completion):
            activityWaiter?.cancel()
            authorizationUI.beginCompletionPresentation()
            completion(receipt)
            authorizationUI.clear()

        case .replace(let makeReplacement):
            activityWaiter?.cancel()
            authorizationUI.beginCompletionPresentation()
            guard let replacement = makeReplacement(receipt),
                  await executionSession.replaceCompletion(with: replacement)
            else {
                let error = InvariantError.completionPresentationFailed("replacement")
                logInvariant(error)
                finishCommittedWithoutPresentation(
                    action.completion,
                    receipt: receipt,
                    authorizationUI: authorizationUI,
                    executionSession: executionSession
                )
                return .completed(receipt)
            }
            Haptics.play(.success)
            authorizationUI.clear()

        case .activity(let completion):
            guard let activityWaiter else {
                let error = InvariantError.invalidConfiguration("activity waiter is missing after commit")
                logInvariant(error)
                finishCommittedWithoutPresentation(
                    action.completion,
                    receipt: receipt,
                    authorizationUI: authorizationUI,
                    executionSession: executionSession
                )
                return .completed(receipt)
            }
            switch await activityWaiter.wait(
                receipt: receipt,
                matches: completion.matches,
                fallbackMatches: completion.fallbackMatches
            ) {
            case .activity(let activity):
                do {
                    authorizationUI.beginCompletionPresentation()
                    let presentation = try await AppActions.makeProtectedActionActivityDetailsPresentation(
                        accountId: action.account.id,
                        activity: activity,
                        context: completion.context
                    )
                    let replacement = Replacement(
                        viewController: presentation.viewController,
                        animateAlongside: presentation.animateAlongside
                    )
                    guard await executionSession.replaceCompletion(with: replacement) else {
                        throw InvariantError.completionPresentationFailed("activity")
                    }
                    Haptics.play(.success)
                    authorizationUI.clear()
                } catch {
                    executorLog.fault(
                        "Protected action committed, but activity completion failed: \(error, .public)"
                    )
                    finishCommittedWithoutPresentation(
                        action.completion,
                        receipt: receipt,
                        authorizationUI: authorizationUI,
                        executionSession: executionSession
                    )
                }

            case .timedOut:
                let error = InvariantError.activityTimedOut(
                    "account=\(action.account.id) title=\(action.confirmation.title)"
                )
                logInvariant(error)
                finishCommittedWithoutPresentation(
                    action.completion,
                    receipt: receipt,
                    authorizationUI: authorizationUI,
                    executionSession: executionSession
                )

            case .cancelled:
                executorLog.info(
                    "Protected action committed before activity observation was cancelled"
                )
                finishCommittedWithoutPresentation(
                    action.completion,
                    receipt: receipt,
                    authorizationUI: authorizationUI,
                    executionSession: executionSession
                )
            }
        }
        return .completed(receipt)
    }

    private static func finishCommittedWithoutPresentation<Result: MfaProtectedActionResult>(
        _ completion: Completion<Result>,
        receipt: ActionSubmissionReceipt<Result>,
        authorizationUI: AuthorizationUI,
        executionSession: ExecutionSession
    ) {
        authorizationUI.dismiss()
        completion.handleCommittedCompletionWithoutPresentation(
            receipt: receipt,
            closeOriginatingFlow: executionSession.closeOriginatingFlow
        )
    }

    private static func logFailure(_ error: any Error) {
        if let invariant = error as? InvariantError {
            logInvariant(invariant)
        } else {
            executorLog.error("Protected action failed: \(error, .public)")
        }
    }

    private static func logTerminalOutcome<Result: MfaProtectedActionResult>(
        _ outcome: Outcome<Result>
    ) {
        switch outcome {
        case .failed(let error):
            executorLog.error("Protected action was not committed: \(error, .public)")
        case .partiallyCommitted(_, let remainingWork):
            executorLog.error(
                "Protected action partially committed: completed=\(remainingWork.completedUnitCount, .public) total=\(remainingWork.totalUnitCount, .public) error=\(remainingWork.error, .public)"
            )
        case .indeterminate(let error, _):
            executorLog.fault(
                "Protected action commit state is indeterminate: \(error, .public)"
            )
        case .completed, .cancelled:
            assertionFailure("Unexpected terminal submission outcome")
        }
    }

    private static func logInvariant(_ error: InvariantError) {
        executorLog.fault("\(error.diagnosticDescription, .public)")
    }
}

extension Completion {
    func handleCommittedCompletionWithoutPresentation(
        receipt: ActionSubmissionReceipt<Result>,
        closeOriginatingFlow: () -> Void
    ) {
        switch self {
        case .finish(let finish), .handoff(let finish):
            finish(receipt)
        case .dismissAuthorization, .replace, .activity:
            closeOriginatingFlow()
        }
    }
}
