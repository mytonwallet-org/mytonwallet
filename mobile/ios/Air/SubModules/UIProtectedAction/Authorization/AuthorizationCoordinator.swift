import SwiftUI
import UIKit
import ProtectedAction
import WalletContext
import WalletCore

enum CompletionBehavior: Sendable, Equatable {
    case popAuthorization
    case keepAuthorizationForReplacement
}

extension Completion {
    var authorizationCompletionBehavior: CompletionBehavior {
        switch self {
        case .dismissAuthorization, .finish:
            .popAuthorization
        case .handoff, .replace, .activity:
            .keepAuthorizationForReplacement
        }
    }
}

@MainActor
enum AuthorizationCoordinator {
    static func authorize<HeaderView: ConfirmationContent, Result: MfaProtectedActionResult>(
        action: ProtectedAction<HeaderView, Result>,
        on viewController: UIViewController,
        completionBehavior: CompletionBehavior,
        authorizationUI: AuthorizationUI,
        isPresentationValid: @escaping @MainActor () -> Bool
    ) async -> ScreenResolution<ActionSubmissionResult<Result>> {
        guard isPresentationValid() else {
            return .cancelled(
                .init(
                    stage: action.account.isHardware ? .ledger : .authentication,
                    reason: .dismissed
                )
            )
        }
        if action.account.isHardware {
            guard let makeOperation = action.hardware else {
                return .failed(
                    DisplayError(text: lang("Transaction to this smart contract is not yet supported by Ledger."))
                )
            }
            return await LedgerPresenter.authorize(
                makeOperation: makeOperation,
                confirmation: action.confirmation,
                on: viewController,
                completionBehavior: completionBehavior,
                authorizationUI: authorizationUI,
                isPresentationValid: isPresentationValid
            )
        }

        let passwordResolution = await PasswordPresenter.authorize(
            account: action.account,
            software: action.software,
            confirmation: action.confirmation,
            on: viewController,
            completionBehavior: completionBehavior,
            authorizationUI: authorizationUI,
            isPresentationValid: isPresentationValid
        )
        switch passwordResolution {
        case .value(.requiresMfa(let result), _):
            guard let requestHash = result.mfaRequestHash else {
                return .failed(
                    InvariantError.missingResult("MFA request hash")
                )
            }
            return await MfaPresenter.authorize(
                account: action.account,
                requestHash: requestHash,
                title: action.confirmation.title,
                compactRepresentation: AnyView(action.confirmation.headerView.compactRepresentation),
                prefersNavigationTitleWithCustomHeader: action.confirmation.prefersNavigationTitleWithCustomHeader,
                result: result,
                software: action.software,
                presentationStyle: action.confirmation.presentationStyle,
                on: viewController,
                completionBehavior: completionBehavior,
                authorizationUI: authorizationUI
            )

        case .value(.resolved(let result), let shouldContinuePresentation):
            return .value(
                result,
                shouldContinuePresentation: shouldContinuePresentation
            )

        case .cancelled(let cancellation):
            return .cancelled(cancellation)

        case .failed(let error):
            return .failed(error)
        }
    }
}
