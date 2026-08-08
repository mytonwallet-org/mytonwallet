import ProtectedAction
import WalletContext
import WalletCore

enum SubmissionFeedback {
    case notCommitted(any Error)
    case partiallyCommitted(ActionRemainingWork)
    case indeterminate(any Error)

    var title: String? {
        switch self {
        case .notCommitted:
            nil
        case .partiallyCommitted:
            lang("Action Partially Completed")
        case .indeterminate:
            lang("Action Status Unknown")
        }
    }

    var message: String? {
        switch self {
        case .notCommitted:
            nil
        case .partiallyCommitted(let remainingWork):
            lang(
                "$action_partially_completed_description",
                arg1: localizedIntegerString(remainingWork.completedUnitCount),
                arg2: localizedIntegerString(remainingWork.totalUnitCount)
            )
        case .indeterminate:
            lang("$action_status_unknown_description")
        }
    }
}

@MainActor
enum SubmissionFeedbackHandler {
    static func handle<Result: MfaProtectedActionResult>(
        _ submission: ActionSubmissionResult<Result>,
        authorizationUI: AuthorizationUI,
        closeOriginatingFlow: () -> Void
    ) async -> Outcome<Result>? {
        switch submission {
        case .committed:
            return nil

        case .notCommitted(let error):
            await authorizationUI.present(.notCommitted(error))
            authorizationUI.dismiss()
            return .failed(error)

        case .partiallyCommitted(let receipt, let remainingWork):
            await authorizationUI.present(.partiallyCommitted(remainingWork))
            authorizationUI.dismiss()
            closeOriginatingFlow()
            return .partiallyCommitted(receipt: receipt, remainingWork: remainingWork)

        case .indeterminate(let error, let receipt):
            await authorizationUI.present(.indeterminate(error))
            authorizationUI.dismiss()
            closeOriginatingFlow()
            return .indeterminate(error: error, receipt: receipt)
        }
    }
}
